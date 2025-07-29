package aiengine

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"simulator/internal/constants"
	"time"
)


func CallAIEngineAPI(flag string) error {
	client := &http.Client{Timeout: 0}
	var url string
	var successMsg, errorMsg string
	var maxRetries int
	var retryDelay time.Duration

	if flag == "ON" {
		url = constants.APIURLAIEngine
		successMsg = "AI-Engine API called successfully."
		errorMsg = "Error calling AI-Engine API"
		maxRetries = 5
		retryDelay = 3 * time.Second
	} else {
		url = constants.APIURLAIEngineStop
		successMsg = "AI-Engine STOP API called successfully."
		errorMsg = "Error calling AI-Engine STOP API"
		maxRetries = 5
		retryDelay = 3 * time.Second
	}

	var lastErr error
	for i := 0; i < maxRetries; i++ {
		resp, err := client.Post(url, "application/json", nil)
		if err != nil {
			lastErr = err
			fmt.Fprintf(os.Stderr, "%s%s%s: %s%s (attempt %d/%d): %v. Retrying in %v...%s\n",
				constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset,
				constants.ColorRed, errorMsg, i+1, maxRetries, err, retryDelay, constants.ColorReset)
			time.Sleep(retryDelay)
			continue
		}

		if resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			fmt.Printf("%s%s%s: %s%s%s\n",
				constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset, constants.ColorGreen, successMsg, constants.ColorReset)
			return nil
		}

		body, _ := ioutil.ReadAll(resp.Body)
		resp.Body.Close()
		lastErr = fmt.Errorf("%s returned non-OK status: %s, body: %s", url, resp.Status, string(body))
		fmt.Fprintf(os.Stderr, "%s%s%s: %s%v (attempt %d/%d). Retrying in %v...%s\n",
			constants.ColorCyan, constants.LogPrefixAIEngine, constants.ColorReset,
			constants.ColorRed, lastErr, i+1, maxRetries, retryDelay, constants.ColorReset)
		time.Sleep(retryDelay)
	}

	return fmt.Errorf("Failed to call %s after %d attempts: %w", url, maxRetries, lastErr)
}
