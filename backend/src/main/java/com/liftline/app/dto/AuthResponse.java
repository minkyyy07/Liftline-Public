package com.liftline.app.dto;

import java.util.UUID;

public class AuthResponse {
    private String token;
    private String accessToken;
    private String refreshToken;
    private String tokenType = "Bearer";
    private long expiresIn;
    private UUID userId;
    private String email;
    private String displayName;

    public AuthResponse() {}

    public AuthResponse(String token, String email) {
        this.token = token;
        this.accessToken = token;
        this.email = email;
    }

    public AuthResponse(String accessToken, String refreshToken, long expiresIn, UUID userId, String email, String displayName) {
        this.token = accessToken;
        this.accessToken = accessToken;
        this.refreshToken = refreshToken;
        this.tokenType = "Bearer";
        this.expiresIn = expiresIn;
        this.userId = userId;
        this.email = email;
        this.displayName = displayName;
    }

    public String getToken() { return token; }
    public void setToken(String token) {
        this.token = token;
        if (this.accessToken == null) this.accessToken = token;
    }

    public String getAccessToken() { return accessToken; }
    public void setAccessToken(String accessToken) {
        this.accessToken = accessToken;
        if (this.token == null) this.token = accessToken;
    }

    public String getRefreshToken() { return refreshToken; }
    public void setRefreshToken(String refreshToken) { this.refreshToken = refreshToken; }

    public String getTokenType() { return tokenType; }
    public void setTokenType(String tokenType) { this.tokenType = tokenType; }

    public long getExpiresIn() { return expiresIn; }
    public void setExpiresIn(long expiresIn) { this.expiresIn = expiresIn; }

    public UUID getUserId() { return userId; }
    public void setUserId(UUID userId) { this.userId = userId; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
}
