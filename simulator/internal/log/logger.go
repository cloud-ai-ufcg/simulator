package log

import (
	"fmt"
	"log"
	"os"
	"simulator/internal/constants"
	"time"
)

var (
	infoLogger  *log.Logger
	errorLogger *log.Logger
)

func init() {
	infoLogger = log.New(os.Stdout, "", 0)
	errorLogger = log.New(os.Stderr, "", 0)
}

func getPrefix(level string) string {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	timestampColor := constants.ColorBlue
	levelColor := ""
	moduleColor := constants.ColorCyan

	switch level {
	case "INFO":
		levelColor = constants.ColorGreen
	case "ERROR":
		levelColor = constants.ColorRed
	default:
		levelColor = constants.ColorReset
	}

	return fmt.Sprintf("%s[%s]%s %s[%s]%s %s[Simulator]%s ",
		timestampColor, timestamp, constants.ColorReset,
		levelColor, level, constants.ColorReset,
		moduleColor, constants.ColorReset)
}

func Infof(format string, v ...interface{}) {
	prefix := getPrefix("INFO")
	infoLogger.Printf(prefix+format, v...)
}

func Errorf(format string, v ...interface{}) {
	prefix := getPrefix("ERROR")
	errorLogger.Printf(prefix+format, v...)
}

func Println(a ...interface{}) {
	fmt.Println(a...)
}
