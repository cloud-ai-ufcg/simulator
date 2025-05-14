package writer

import (
	"encoding/csv"
	"os"
)

// CSVWriter handles writing metrics to CSV files
type CSVWriter struct {
	file   *os.File
	writer *csv.Writer
}

// NewCSVWriter creates a new CSV writer with the given filename and headers
func NewCSVWriter(filename string, headers []string) (*CSVWriter, error) {
	file, err := os.Create(filename)
	if err != nil {
		return nil, err
	}

	writer := csv.NewWriter(file)
	if err := writer.Write(headers); err != nil {
		file.Close()
		return nil, err
	}

	return &CSVWriter{
		file:   file,
		writer: writer,
	}, nil
}

// Write writes a row of data to the CSV file
func (w *CSVWriter) Write(data []string) error {
	return w.writer.Write(data)
}

// Flush writes any buffered data to the underlying file
func (w *CSVWriter) Flush() {
	w.writer.Flush()
}

// Close closes the underlying file
func (w *CSVWriter) Close() error {
	w.Flush()
	return w.file.Close()
} 