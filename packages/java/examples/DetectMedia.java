package com.neuraldefend.examples;

import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.VideoOptions;
import com.neuraldefend.VideoResult;

/** Example image and video detection against NeuroVerify. */
public final class DetectMedia {
    public static void main(String[] args) throws Exception {
        ClientOptions options = new ClientOptions();
        options.apiKey = System.getenv("NEURALDEFEND_API_KEY");
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        String imagePath = args.length > 0 ? args[0] : "selfie.jpg";
        var imageResult = client.detectImage(Media.fileMedia(imagePath));
        System.out.printf(
                "image: status=%s scored=%s message=%s%n",
                imageResult.status, imageResult.scored(), imageResult.message);

        if (args.length > 1) {
            VideoResult videoResult =
                    client.detectVideo(Media.fileMedia(args[1]), new VideoOptions());
            System.out.printf(
                    "video: status=%s scored=%s overall=%s message=%s%n",
                    videoResult.status,
                    videoResult.scored(),
                    videoResult.overallRiskScore(),
                    videoResult.videoMessage);
        }
    }
}
