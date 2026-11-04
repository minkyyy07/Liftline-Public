package com.liftline.app.service;

import com.liftline.app.entity.RefreshSession;
import com.liftline.app.entity.User;
import com.liftline.app.repository.RefreshSessionRepository;
import com.liftline.app.security.JwtProperties;
import com.liftline.app.security.JwtService;
import com.liftline.app.security.TokenReuseException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;

@Service
@Transactional(noRollbackFor = TokenReuseException.class)
public class RefreshTokenService {

    private final RefreshSessionRepository refreshSessionRepository;
    private final JwtService jwtService;
    private final JwtProperties jwtProperties;
    private final SecureRandom secureRandom = new SecureRandom();

    public RefreshTokenService(RefreshSessionRepository refreshSessionRepository,
                               JwtService jwtService,
                               JwtProperties jwtProperties) {
        this.refreshSessionRepository = refreshSessionRepository;
        this.jwtService = jwtService;
        this.jwtProperties = jwtProperties;
    }

    public static class TokenPair {
        private final String accessToken;
        private final String rawRefreshToken;
        private final UUID familyId;
        private final Instant expiresAt;
        private final User user;

        public TokenPair(String accessToken, String rawRefreshToken, UUID familyId, Instant expiresAt, User user) {
            this.accessToken = accessToken;
            this.rawRefreshToken = rawRefreshToken;
            this.familyId = familyId;
            this.expiresAt = expiresAt;
            this.user = user;
        }

        public String getAccessToken() { return accessToken; }
        public String getRawRefreshToken() { return rawRefreshToken; }
        public UUID getFamilyId() { return familyId; }
        public Instant getExpiresAt() { return expiresAt; }
        public User getUser() { return user; }
    }

    public static String hashToken(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) {
            throw new BadCredentialsException("Refresh token must not be blank");
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(rawToken.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 algorithm unavailable", e);
        }
    }

    public String generateRawToken() {
        byte[] bytes = new byte[32];
        secureRandom.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    public TokenPair createSession(User user, String userAgent, String clientIp) {
        String rawToken = generateRawToken();
        String tokenHash = hashToken(rawToken);
        UUID familyId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plus(jwtProperties.getRefreshTokenDays(), ChronoUnit.DAYS);

        RefreshSession session = new RefreshSession(user, tokenHash, familyId, expiresAt);
        session.setUserAgent(userAgent);
        session.setClientIp(clientIp);
        refreshSessionRepository.save(session);

        String accessToken = jwtService.generateToken(user);
        return new TokenPair(accessToken, rawToken, familyId, expiresAt, user);
    }

    public TokenPair rotateSession(String rawRefreshToken, String userAgent, String clientIp) {
        String tokenHash = hashToken(rawRefreshToken);
        RefreshSession session = refreshSessionRepository.findByTokenHashForUpdate(tokenHash)
                .orElseThrow(() -> new BadCredentialsException("Invalid refresh token"));

        if (session.getExpiresAt().isBefore(Instant.now())) {
            throw new BadCredentialsException("Refresh token expired");
        }

        if (session.isRevoked()) {
            // Token reuse detected! Revoke the entire family
            refreshSessionRepository.revokeAllByFamilyId(session.getFamilyId());
            throw new TokenReuseException("Token reuse detected. All sessions in this chain have been revoked.");
        }

        // Revoke the old token
        session.setRevoked(true);
        session.setReplacedAt(Instant.now());
        refreshSessionRepository.save(session);

        // Issue new token in the same family
        String newRawToken = generateRawToken();
        String newHash = hashToken(newRawToken);
        Instant newExpiresAt = Instant.now().plus(jwtProperties.getRefreshTokenDays(), ChronoUnit.DAYS);

        RefreshSession newSession = new RefreshSession(session.getUser(), newHash, session.getFamilyId(), newExpiresAt);
        newSession.setUserAgent(userAgent);
        newSession.setClientIp(clientIp);
        refreshSessionRepository.save(newSession);

        String accessToken = jwtService.generateToken(session.getUser());
        return new TokenPair(accessToken, newRawToken, session.getFamilyId(), newExpiresAt, session.getUser());
    }

    public void revokeSession(String rawRefreshToken) {
        if (rawRefreshToken == null || rawRefreshToken.isBlank()) return;
        try {
            String tokenHash = hashToken(rawRefreshToken);
            refreshSessionRepository.findByTokenHash(tokenHash).ifPresent(s -> {
                s.setRevoked(true);
                refreshSessionRepository.save(s);
            });
        } catch (Exception ignored) {
            // No error leak on logout
        }
    }

    public void revokeAllForUser(UUID userId) {
        if (userId != null) {
            refreshSessionRepository.revokeAllByUserId(userId);
        }
    }
}
