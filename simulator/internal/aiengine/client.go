package aiengine

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"simulator/internal/constants"
	"time"
)

// CallAIEngineAPI sends a request to the AI Engine API, retrying up to 10 times on failure.
func CallAIEngineAPI(apiURL string) error {
	client := &http.Client{
		Timeout: 0,
	}

	const maxRetries = 10
	var lastErr error

	for i := 0; i < maxRetries; i++ {
		resp, err := client.Post(apiURL, "application/json", nil)
		if err != nil {
			lastErr = err
			fmt.Fprintf(os.Stderr, "%s%s%s: %sError calling AI-Engine API (attempt %d/%d): %v. Retrying in 5 seconds...%s\n",
				constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset,
				constants.ColorRed, i+1, maxRetries, err, constants.ColorReset)
			time.Sleep(5 * time.Second)
			continue
		}

		if resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			fmt.Printf("%s%s%s: %sAI-Engine API called successfully.%s\n",
				constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorGreen, constants.ColorReset)
			return nil
		}

		body, _ := ioutil.ReadAll(resp.Body)
		resp.Body.Close()
		lastErr = fmt.Errorf("ai-engine API returned non-OK status: %s, body: %s", resp.Status, string(body))
		fmt.Fprintf(os.Stderr, "%s%s%s: %s%v (attempt %d/%d). Retrying in 5 seconds...%s\n",
			constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset,
			constants.ColorRed, lastErr, i+1, maxRetries, constants.ColorReset)

		time.Sleep(5 * time.Second)
	}

	return fmt.Errorf("failed to call AI-Engine API after %d attempts: %w", maxRetries, lastErr)
}
