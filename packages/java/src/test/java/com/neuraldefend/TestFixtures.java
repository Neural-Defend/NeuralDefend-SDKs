package com.neuraldefend;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonPrimitive;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class TestFixtures {
    private static final Gson GSON = new GsonBuilder().serializeNulls().create();
    private static final Path FIXTURES_ROOT =
            Path.of("..", "..", "tests", "fixtures").toAbsolutePath().normalize();

    private TestFixtures() {}

    static Map<String, Object> loadCase(String relativePath) throws IOException {
        String raw = Files.readString(FIXTURES_ROOT.resolve(relativePath), StandardCharsets.UTF_8);
        return jsonObjectToMap(JsonParser.parseString(raw).getAsJsonObject());
    }

    static ResponseParts responseFromCase(Map<String, Object> caseData) {
        int status = ((Number) caseData.get("http_status")).intValue();
        Map<String, String> headers = new HashMap<>();
        Object rawHeaders = caseData.get("headers");
        if (rawHeaders instanceof Map<?, ?> headerMap) {
            for (Map.Entry<?, ?> entry : headerMap.entrySet()) {
                headers.put(String.valueOf(entry.getKey()), String.valueOf(entry.getValue()));
            }
        }
        byte[] body;
        if ("raw".equals(caseData.get("body_kind"))) {
            Object payload = caseData.get("body");
            body =
                    payload instanceof String stringPayload
                            ? stringPayload.getBytes(StandardCharsets.UTF_8)
                            : GSON.toJson(payload).getBytes(StandardCharsets.UTF_8);
        } else {
            body = GSON.toJson(caseData.get("body")).getBytes(StandardCharsets.UTF_8);
        }
        return new ResponseParts(status, headers, body);
    }

    private static Map<String, Object> jsonObjectToMap(JsonObject object) {
        Map<String, Object> map = new HashMap<>();
        for (Map.Entry<String, JsonElement> entry : object.entrySet()) {
            map.put(entry.getKey(), jsonElementToValue(entry.getValue()));
        }
        return map;
    }

    private static Object jsonElementToValue(JsonElement element) {
        if (element == null || element instanceof JsonNull) {
            return null;
        }
        if (element.isJsonObject()) {
            return jsonObjectToMap(element.getAsJsonObject());
        }
        if (element.isJsonArray()) {
            JsonArray array = element.getAsJsonArray();
            List<Object> values = new ArrayList<>(array.size());
            for (JsonElement item : array) {
                values.add(jsonElementToValue(item));
            }
            return values;
        }
        JsonPrimitive primitive = element.getAsJsonPrimitive();
        if (primitive.isBoolean()) {
            return primitive.getAsBoolean();
        }
        if (primitive.isString()) {
            return primitive.getAsString();
        }
        if (primitive.isNumber()) {
            return primitive.getAsDouble();
        }
        return null;
    }

    record ResponseParts(int status, Map<String, String> headers, byte[] body) {}
}
