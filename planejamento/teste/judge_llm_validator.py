"""
Judge/LLM Validator Module

Receives recommendations from AI-Engine, validates them with an LLM,
and returns only approved recommendations to Actuator.

Architecture:
    AI-Engine → Judge/LLM Validator → Actuator
"""

import json
import asyncio
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, asdict
from enum import Enum

import aiohttp
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


class RecommendationStatus(str, Enum):
    """Status of a recommendation after LLM validation"""
    APPROVED = "approved"
    REJECTED = "rejected"
    REQUIRES_REVIEW = "requires_review"


@dataclass
class ValidatedRecommendation:
    """Recommendation with LLM validation result"""
    workload_id: str
    destination_cluster: int
    kind: str
    llm_score: float  # 0.0 to 1.0
    llm_status: str  # approved, rejected, requires_review
    llm_reasoning: str  # Why LLM approved/rejected
    original_recommendation: Dict[str, Any]


class RecommendationsRequest(BaseModel):
    """Request body with recommendations from AI-Engine"""
    batch_id: int
    recommendations: List[Dict[str, Any]]
    monitoring_data: Optional[Dict[str, Any]] = None  # Context for LLM


class JudgeValidator:
    """Main validator class that handles LLM validation"""

    def __init__(self, llm_provider: str = "anthropic"):
        self.llm_provider = llm_provider
        self.api_key = None  # Will be loaded from config
        self.llm_threshold = 0.7  # Threshold for approval

    async def validate_recommendations(
        self,
        recommendations: List[Dict[str, Any]],
        monitoring_data: Optional[Dict[str, Any]] = None,
    ) -> List[ValidatedRecommendation]:
        """
        Validate each recommendation with LLM and return results

        Args:
            recommendations: List of recommendations from AI-Engine
            monitoring_data: Context about cluster state

        Returns:
            List of ValidatedRecommendation objects
        """
        validated = []

        for rec in recommendations:
            # Build prompt for LLM evaluation
            prompt = self._build_validation_prompt(rec, monitoring_data)

            # Call LLM
            llm_response = await self._call_llm(prompt)

            # Parse LLM response
            result = self._parse_llm_response(rec, llm_response)

            validated.append(result)

        return validated

    def _build_validation_prompt(
        self,
        recommendation: Dict[str, Any],
        monitoring_data: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        Build prompt to send to LLM for validation

        Prompt includes:
        - Evaluation criteria
        - Recommendation details
        - Cluster context
        """

        prompt = f"""
You are a Kubernetes workload migration validator. Evaluate if this recommendation makes sense.

EVALUATION CRITERIA:
1. Will migration reduce costs without violating SLA?
2. Is the destination cluster healthy and has capacity?
3. Is the workload type suitable for migration?
4. Are there any critical production risks?
5. Is the timing appropriate?

RECOMMENDATION TO EVALUATE:
- Workload ID: {recommendation.get('workload_id')}
- Kind: {recommendation.get('kind')}
- Source Cluster: {recommendation.get('current_cluster', 'unknown')}
- Destination Cluster: {recommendation.get('destination_cluster')}
- Expected Cost Reduction: {recommendation.get('cost_reduction', 'unknown')}%
- Replicas: {recommendation.get('replicas', 1)}
- CPU Requested: {recommendation.get('cpu', 'unknown')}
- Memory Requested: {recommendation.get('memory', 'unknown')}

CLUSTER CONTEXT:
{json.dumps(monitoring_data or {}, indent=2)}

INSTRUCTIONS:
1. Evaluate the recommendation based on criteria above
2. Respond in JSON format ONLY:
{{
    "decision": "approved|rejected|requires_review",
    "confidence_score": 0.0 to 1.0,
    "reasoning": "Brief explanation of your decision",
    "risks": ["list", "of", "identified", "risks"],
    "recommendations": "Additional suggestions if any"
}}

3. Be strict - only approve if truly beneficial
4. Consider both cost and reliability
"""
        return prompt

    async def _call_llm(self, prompt: str) -> str:
        """
        Call the LLM API with the validation prompt

        Could use any LLM: OpenAI, Anthropic, Groq, Google, etc.
        """
        # Example using Anthropic Claude
        # In real implementation, would use same setup as AI-Engine

        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }

        payload = {
            "model": "claude-3-sonnet-20240229",
            "max_tokens": 500,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                "https://api.anthropic.com/v1/messages",
                json=payload,
                headers=headers,
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    return data["content"][0]["text"]
                else:
                    raise Exception(f"LLM API error: {response.status}")

    def _parse_llm_response(
        self,
        original_recommendation: Dict[str, Any],
        llm_response: str,
    ) -> ValidatedRecommendation:
        """
        Parse LLM JSON response and create ValidatedRecommendation
        """
        try:
            # Extract JSON from LLM response
            json_start = llm_response.find("{")
            json_end = llm_response.rfind("}") + 1
            json_str = llm_response[json_start:json_end]
            parsed = json.loads(json_str)

            # Map LLM decision to status
            decision = parsed.get("decision", "rejected").lower()
            if decision == "approved":
                status = RecommendationStatus.APPROVED
            elif decision == "requires_review":
                status = RecommendationStatus.REQUIRES_REVIEW
            else:
                status = RecommendationStatus.REJECTED

            return ValidatedRecommendation(
                workload_id=original_recommendation.get("workload_id"),
                destination_cluster=original_recommendation.get("destination_cluster"),
                kind=original_recommendation.get("kind"),
                llm_score=float(parsed.get("confidence_score", 0.0)),
                llm_status=status,
                llm_reasoning=parsed.get("reasoning", "No reasoning provided"),
                original_recommendation=original_recommendation,
            )

        except Exception as e:
            # If parsing fails, reject by default (safe approach)
            print(f"Error parsing LLM response: {e}")
            return ValidatedRecommendation(
                workload_id=original_recommendation.get("workload_id"),
                destination_cluster=original_recommendation.get("destination_cluster"),
                kind=original_recommendation.get("kind"),
                llm_score=0.0,
                llm_status=RecommendationStatus.REJECTED,
                llm_reasoning="Failed to parse LLM response",
                original_recommendation=original_recommendation,
            )


# FastAPI App
app = FastAPI(
    title="Judge/LLM Validator",
    description="Validates AI-Engine recommendations using LLM",
    version="1.0.0",
)

validator = JudgeValidator()


@app.get("/")
async def health():
    """Health check"""
    return {"status": "healthy", "service": "Judge/LLM Validator"}


@app.post("/validate")
async def validate_recommendations(request: RecommendationsRequest) -> Dict[str, Any]:
    """
    Main endpoint: receives recommendations from AI-Engine,
    validates them with LLM, returns filtered results

    Example request:
    POST /validate
    {
        "batch_id": 1,
        "recommendations": [
            {"workload_id": "1000", "destination_cluster": 1, ...}
        ],
        "monitoring_data": {...cluster context...}
    }

    Returns:
    {
        "batch_id": 1,
        "validated_recommendations": [...],
        "summary": {
            "total_evaluated": 10,
            "approved": 7,
            "rejected": 3,
            "requires_review": 0
        }
    }
    """
    try:
        # Validate all recommendations with LLM
        validated_list = await validator.validate_recommendations(
            request.recommendations,
            request.monitoring_data,
        )

        # Count results
        approved = [
            r for r in validated_list
            if r.llm_status == RecommendationStatus.APPROVED
        ]
        rejected = [
            r for r in validated_list
            if r.llm_status == RecommendationStatus.REJECTED
        ]
        requires_review = [
            r for r in validated_list
            if r.llm_status == RecommendationStatus.REQUIRES_REVIEW
        ]

        # Prepare response
        response = {
            "batch_id": request.batch_id,
            "validated_recommendations": [asdict(r) for r in validated_list],
            "approved_recommendations": [asdict(r) for r in approved],
            "summary": {
                "total_evaluated": len(validated_list),
                "approved": len(approved),
                "rejected": len(rejected),
                "requires_review": len(requires_review),
                "approval_rate": len(approved) / len(validated_list) if validated_list else 0,
            }
        }

        return response

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/validate-and-apply")
async def validate_and_apply(request: RecommendationsRequest) -> Dict[str, Any]:
    """
    Full flow: validate AND send approved ones to Actuator

    This would be called by Simulator instead of calling AI-Engine → Actuator directly
    """
    try:
        # Step 1: Validate with LLM
        validation_result = await validate_recommendations(request)

        # Step 2: Extract only approved
        approved = validation_result["approved_recommendations"]

        # Step 3: Send to Actuator
        if approved:
            await _send_to_actuator(approved)

        return {
            "status": "success",
            "message": f"Sent {len(approved)} approved recommendations to Actuator",
            "validation_result": validation_result,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


async def _send_to_actuator(recommendations: List[Dict[str, Any]]) -> None:
    """
    Helper: sends approved recommendations to Actuator

    This is what Simulator would normally do,
    but now Judge does it after validation
    """
    actuator_url = "http://localhost:8080/actuate"  # Or from config

    payload = json.dumps(recommendations)

    async with aiohttp.ClientSession() as session:
        async with session.post(
            actuator_url,
            data=payload,
            headers={"Content-Type": "application/json"},
        ) as response:
            if response.status not in [200, 202]:
                raise Exception(f"Actuator returned {response.status}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "judge_llm_validator:app",
        host="0.0.0.0",
        port=8084,  # Different port than other services
        reload=False,
    )
