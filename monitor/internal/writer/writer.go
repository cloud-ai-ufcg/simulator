package writer

import (
	"encoding/json"
	"os"
	"sync"

	"monitor/internal/model"
)

type Writer struct {
	filepath string
	mu       sync.Mutex
}

func NewWriter(filepath string) *Writer {
	return &Writer{
		filepath: filepath,
	}
}

func (w *Writer) WriteMetrics(metrics map[int64]model.MetricsOutput) error {
	w.mu.Lock()
	defer w.mu.Unlock()

	// Read existing metrics if file exists
	var existingMetrics map[int64]model.MetricsOutput
	if _, err := os.Stat(w.filepath); err == nil {
		file, err := os.Open(w.filepath)
		if err != nil {
			return err
		}
		defer file.Close()

		decoder := json.NewDecoder(file)
		if err := decoder.Decode(&existingMetrics); err != nil {
			return err
		}
	} else {
		existingMetrics = make(map[int64]model.MetricsOutput)
	}

	// Merge new metrics with existing ones
	for timestamp, metricOutput := range metrics {
		existingMetrics[timestamp] = metricOutput
	}

	// Write all metrics back to file
	file, err := os.Create(w.filepath)
	if err != nil {
		return err
	}
	defer file.Close()

	// Encode metrics to JSON
	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	return encoder.Encode(existingMetrics)
}
