package com.neuraldefend;

import java.util.List;
import java.util.Map;
import java.util.Set;

/** Video scoring or business-rejection result. */
public final class VideoResult {
    private static final Set<String> RISK_LEVELS = Set.of("low", "medium", "high");

    public final String uniqueTrxId;
    public final String filename;
    public final String contentType;
    public final String status;
    public final int statusCode;
    public final boolean billable;
    public final Double videoRiskScore;
    public final String videoRiskLevel;
    public final String videoMessage;
    public final Double audioRiskScore;
    public final String audioRiskLevel;
    public final String audioMessage;
    public final List<String> aiThreatSignals;
    public final Map<String, Object> raw;

    public VideoResult(
            String uniqueTrxId,
            String filename,
            String contentType,
            String status,
            int statusCode,
            boolean billable,
            Double videoRiskScore,
            String videoRiskLevel,
            String videoMessage,
            Double audioRiskScore,
            String audioRiskLevel,
            String audioMessage,
            List<String> aiThreatSignals,
            Map<String, Object> raw) {
        this.uniqueTrxId = uniqueTrxId;
        this.filename = filename;
        this.contentType = contentType;
        this.status = status;
        this.statusCode = statusCode;
        this.billable = billable;
        this.videoRiskScore = videoRiskScore;
        this.videoRiskLevel = videoRiskLevel;
        this.videoMessage = videoMessage;
        this.audioRiskScore = audioRiskScore;
        this.audioRiskLevel = audioRiskLevel;
        this.audioMessage = audioMessage;
        this.aiThreatSignals = aiThreatSignals;
        this.raw = raw;
    }

    /** Reports whether both video and audio modalities scored successfully. */
    public boolean scored() {
        boolean videoScored =
                videoRiskScore != null
                        && videoRiskLevel != null
                        && RISK_LEVELS.contains(videoRiskLevel);
        boolean audioScored =
                (audioRiskScore == null && audioRiskLevel == null)
                        || (audioRiskScore != null
                                && audioRiskLevel != null
                                && RISK_LEVELS.contains(audioRiskLevel));
        return "success".equals(status) && videoScored && audioScored;
    }

    /** Reports whether the API rejected the media without throwing. */
    public boolean rejected() {
        return "rejected".equals(status);
    }

    /** Reports whether an audio risk score was returned. */
    public boolean hasAudio() {
        return audioRiskScore != null;
    }

    /** Returns the client-side maximum score; the API has no combined score. */
    public Double overallRiskScore() {
        Double max = null;
        if (videoRiskScore != null) {
            max = videoRiskScore;
        }
        if (audioRiskScore != null) {
            max = max == null ? audioRiskScore : Math.max(max, audioRiskScore);
        }
        return max;
    }
}
