package com.neuraldefend;

import java.util.List;
import java.util.Map;
import java.util.Set;

/** Image scoring or business-rejection result. */
public final class ImageResult {
    private static final Set<String> RISK_LEVELS = Set.of("low", "medium", "high");

    public final String uniqueTrxId;
    public final String filename;
    public final String contentType;
    public final String status;
    public final int statusCode;
    public final boolean billable;
    public final Double riskScore;
    public final String riskLevel;
    public final String message;
    public final List<String> aiThreatSignals;
    public final Map<String, Object> raw;

    public ImageResult(
            String uniqueTrxId,
            String filename,
            String contentType,
            String status,
            int statusCode,
            boolean billable,
            Double riskScore,
            String riskLevel,
            String message,
            List<String> aiThreatSignals,
            Map<String, Object> raw) {
        this.uniqueTrxId = uniqueTrxId;
        this.filename = filename;
        this.contentType = contentType;
        this.status = status;
        this.statusCode = statusCode;
        this.billable = billable;
        this.riskScore = riskScore;
        this.riskLevel = riskLevel;
        this.message = message;
        this.aiThreatSignals = aiThreatSignals;
        this.raw = raw;
    }

    /** Reports whether the result contains a successful risk score. */
    public boolean scored() {
        return "success".equals(status)
                && riskScore != null
                && riskLevel != null
                && RISK_LEVELS.contains(riskLevel);
    }

    /** Reports whether the API rejected the media without throwing. */
    public boolean rejected() {
        return "rejected".equals(status);
    }

    /** Reports whether the risk level is high. */
    public boolean highRisk() {
        return "high".equals(riskLevel);
    }
}
