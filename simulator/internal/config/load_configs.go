package config

import (
	"io/ioutil"

	"gopkg.in/yaml.v2"
)

type AIEngineConfig struct {
	Enabled bool `yaml:"enabled"`
}

type Config struct {
	AIEngine AIEngineConfig `yaml:"ai-engine"`
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
