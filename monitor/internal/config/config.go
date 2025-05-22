package config

type ClusterConfig struct {
	Label         string
	PrometheusURL string
}

type Config struct {
	Clusters []ClusterConfig
}

func LoadConfig() (*Config, error) {
	return &Config{
		Clusters: []ClusterConfig{
			{
				Label:         "private",
				PrometheusURL: "http://localhost:9090",
			},
			{
				Label:         "public",
				PrometheusURL: "http://localhost:9091",
			},
		},
	}, nil
}
