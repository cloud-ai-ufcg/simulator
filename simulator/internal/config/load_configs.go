package config

import (
	"io/ioutil"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v2"
)

type AIEngineConfig struct {
	Enabled bool `yaml:"enabled"`
	Server  struct {
		Host string `yaml:"host"`
		Port int    `yaml:"port"`
	} `yaml:"server"`
}

type Config struct {
	AIEngine AIEngineConfig `yaml:"ai-engine"`
}

// AIEngineModuleFallback mirrors the structure used by ai-engine/config.yaml
type AIEngineModuleFallback struct {
	Server struct {
		Host string `yaml:"host"`
		Port int    `yaml:"port"`
	} `yaml:"server"`
}

func LoadAIEngineEnabled(configPath string) (bool, error) {
	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		return false, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return false, err
	}
	return cfg.AIEngine.Enabled, nil
}

// LoadAIEngineServer returns the host and port for the AI-Engine server from the simulator config.
// If host is 0.0.0.0, we return localhost for client connections.
func LoadAIEngineServer(configPath string) (string, int, error) {
	// Prefer simulator config
	data, err := ioutil.ReadFile(configPath)
	var cfg Config
	if err == nil {
		_ = yaml.Unmarshal(data, &cfg)
	}

	host := cfg.AIEngine.Server.Host
	port := cfg.AIEngine.Server.Port

	// Fallback to ai-engine/config.yaml if missing
	if host == "" || port == 0 {
		if fh, fp, ok := loadAIEngineServerFromModule(configPath); ok {
			if host == "" {
				host = fh
			}
			if port == 0 {
				port = fp
			}
		}
	}

	if host == "0.0.0.0" || host == "" {
		host = "127.0.0.1"
	}
	if port == 0 {
		port = 8083
	}
	return host, port, nil
}

// loadAIEngineServerFromModule tries common locations for ai-engine/config.yaml
func loadAIEngineServerFromModule(simulatorConfigPath string) (string, int, bool) {
	candidates := []string{}

	if simulatorConfigPath != "" {
		cfgDir := filepath.Dir(simulatorConfigPath)
		upOne := filepath.Dir(cfgDir)
		upTwo := filepath.Dir(upOne)
		candidates = append(candidates,
			filepath.Join(upTwo, "ai-engine", "config.yaml"),
			filepath.Join(upOne, "ai-engine", "config.yaml"),
		)
	}

	candidates = append(candidates,
		"../../ai-engine/config.yaml",
		"../ai-engine/config.yaml",
		"./ai-engine/config.yaml",
		"ai-engine/config.yaml",
	)

	var fallback AIEngineModuleFallback
	for _, p := range candidates {
		if p == "" {
			continue
		}
		if _, err := os.Stat(p); err != nil {
			continue
		}
		b, err := ioutil.ReadFile(p)
		if err != nil {
			continue
		}
		if err := yaml.Unmarshal(b, &fallback); err != nil {
			continue
		}
		h := fallback.Server.Host
		pt := fallback.Server.Port
		if h != "" || pt != 0 {
			return h, pt, true
		}
	}
	return "", 0, false
}
