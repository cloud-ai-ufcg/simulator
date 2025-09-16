package aiengine

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"simulator/internal/constants"
	"simulator/internal/log"
	"time"
)

func CallAIEngineAPI(enabled bool) error {
	client := &http.Client{Timeout: 0}
	var url string
	var successMsg, errorMsg string
	var maxRetries int = 5
	var retryDelay time.Duration = 3 * time.Second

	if enabled {
		url = constants.APIURLAIEngine
		successMsg = "AI-Engine API called successfully."
		errorMsg = "Error calling AI-Engine API"
	} else {
		url = constants.APIURLAIEngineStop
		successMsg = "AI-Engine STOP API called successfully."
		errorMsg = "Error calling AI-Engine STOP API"
	}

	var lastErr error
	for i := 0; i < maxRetries; i++ {
		resp, err := client.Post(url, "application/json", nil)
		if err != nil {
			lastErr = err
			log.Errorf("%s (attempt %d/%d): %v. Retrying in %v...", errorMsg, i+1, maxRetries, err, retryDelay)
			time.Sleep(retryDelay)
			continue
		}

		if resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			log.Infof("%s", successMsg)
			return nil
		}

		body, _ := ioutil.ReadAll(resp.Body)
		resp.Body.Close()
		lastErr = fmt.Errorf("%s returned non-OK status: %s, body: %s", url, resp.Status, string(body))
		log.Errorf("%v (attempt %d/%d). Retrying in %v...", lastErr, i+1, maxRetries, retryDelay)
		time.Sleep(retryDelay)
	}

	return fmt.Errorf("Failed to call %s after %d attempts: %w", url, maxRetries, lastErr)
}
