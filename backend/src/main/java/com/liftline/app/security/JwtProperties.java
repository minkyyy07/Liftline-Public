package com.liftline.app.security;

import jakarta.annotation.PostConstruct;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

@Component
@ConfigurationProperties(prefix = "jwt")
public class JwtProperties {
    private String secret;
    private long expirationMs = 900000; // 15 minutes default access token
    private int refreshTokenDays = 30; // 30 days default refresh session

    @PostConstruct
    public void validate() {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException(
                "JWT secret is not configured. Please set JWT_SECRET environment variable (minimum 32 bytes)."
            );
        }
        if (secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                String.format(
                    "JWT secret is too short: length is %d bytes, but at least 32 bytes (256 bits) required. Please update JWT_SECRET.",
                    secret.getBytes(StandardCharsets.UTF_8).length
                )
            );
        }
    }

    public String getSecret() { return secret; }
    public void setSecret(String secret) { this.secret = secret; }
    public long getExpirationMs() { return expirationMs; }
    public void setExpirationMs(long expirationMs) { this.expirationMs = expirationMs; }
    public int getRefreshTokenDays() { return refreshTokenDays; }
    public void setRefreshTokenDays(int refreshTokenDays) { this.refreshTokenDays = refreshTokenDays; }
}
