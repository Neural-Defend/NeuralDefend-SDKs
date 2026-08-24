package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/Neural-Defend/NeuralDefend-SDKs/packages/go"
)

func main() {
	client, err := neuraldefend.NewClient(neuraldefend.ClientOptions{
		APIKey: os.Getenv("NEURALDEFEND_API_KEY"),
	})
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()

	imagePath := "selfie.jpg"
	if len(os.Args) > 1 {
		imagePath = os.Args[1]
	}
	imageResult, err := client.DetectImage(ctx, neuraldefend.FileMedia(imagePath))
	if err != nil {
		log.Fatalf("image detection failed: %v", err)
	}
	fmt.Printf("image: status=%s scored=%t message=%q\n", imageResult.Status, imageResult.Scored(), imageResult.Message)

	if len(os.Args) > 2 {
		videoResult, err := client.DetectVideo(ctx, neuraldefend.FileMedia(os.Args[2]), neuraldefend.VideoOptions{})
		if err != nil {
			log.Fatalf("video detection failed: %v", err)
		}
		fmt.Printf(
			"video: status=%s scored=%t overall=%v message=%q\n",
			videoResult.Status,
			videoResult.Scored(),
			videoResult.OverallRiskScore(),
			videoResult.VideoMessage,
		)
	}
}
