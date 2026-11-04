package com.liftline.app.controller;

import com.liftline.app.dto.AuthRequest;
import com.liftline.app.dto.AuthResponse;
import com.liftline.app.dto.RefreshTokenRequest;
import com.liftline.app.entity.User;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.security.AuthRateLimiter;
import com.liftline.app.security.JwtService;
import com.liftline.app.service.RefreshTokenService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final AuthenticationManager authenticationManager;
    private final JwtService jwtService;
    private final RefreshTokenService refreshTokenService;
    private final AuthRateLimiter authRateLimiter;

    public AuthController(UserRepository userRepository,
                          PasswordEncoder passwordEncoder,
                          AuthenticationManager authenticationManager,
                          JwtService jwtService,
                          RefreshTokenService refreshTokenService,
                          AuthRateLimiter authRateLimiter) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.authenticationManager = authenticationManager;
        this.jwtService = jwtService;
        this.refreshTokenService = refreshTokenService;
        this.authRateLimiter = authRateLimiter;
    }

    private String getClientIp(HttpServletRequest request) {
        String xf = request.getHeader("X-Forwarded-For");
        if (xf != null && !xf.isBlank()) {
            return xf.split(",")[0].trim();
        }
        return request.getRemoteAddr() != null ? request.getRemoteAddr() : "unknown";
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@Valid @RequestBody AuthRequest request, HttpServletRequest httpRequest) {
        String clientIp = getClientIp(httpRequest);
        if (!authRateLimiter.tryAcquire("register:" + clientIp)) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .body(Map.of("error", "Too many registration attempts. Please try again later."));
        }

        String normalizedEmail = request.getEmail().trim().toLowerCase();
        if (userRepository.existsByEmail(normalizedEmail)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Email already registered"));
        }

        try {
            User user = new User(normalizedEmail, passwordEncoder.encode(request.getPassword()), request.getDisplayName());
            userRepository.save(user);
            return ResponseEntity.ok(Map.of("message", "User registered successfully"));
        } catch (DataIntegrityViolationException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", "Email already registered"));
        }
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody AuthRequest request, HttpServletRequest httpRequest) {
        String clientIp = getClientIp(httpRequest);
        if (!authRateLimiter.tryAcquire("login:" + clientIp)) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .body(Map.of("error", "Too many login attempts. Please try again later."));
        }

        String normalizedEmail = request.getEmail().trim().toLowerCase();
        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(normalizedEmail, request.getPassword())
        );

        User user = userRepository.findByEmail(normalizedEmail)
                .orElseThrow(() -> new IllegalStateException("User missing after authentication"));

        String userAgent = httpRequest.getHeader("User-Agent");
        RefreshTokenService.TokenPair tokenPair = refreshTokenService.createSession(user, userAgent, clientIp);

        AuthResponse response = new AuthResponse(
                tokenPair.getAccessToken(),
                tokenPair.getRawRefreshToken(),
                jwtService.getExpirationSeconds(),
                user.getId(),
                user.getEmail(),
                user.getDisplayName()
        );
        return ResponseEntity.ok(response);
    }

    @PostMapping("/refresh")
    public ResponseEntity<?> refresh(@Valid @RequestBody RefreshTokenRequest request, HttpServletRequest httpRequest) {
        String clientIp = getClientIp(httpRequest);
        String userAgent = httpRequest.getHeader("User-Agent");

        RefreshTokenService.TokenPair tokenPair = refreshTokenService.rotateSession(
                request.getRefreshToken(), userAgent, clientIp
        );

        AuthResponse response = new AuthResponse(
                tokenPair.getAccessToken(),
                tokenPair.getRawRefreshToken(),
                jwtService.getExpirationSeconds(),
                tokenPair.getUser().getId(),
                tokenPair.getUser().getEmail(),
                tokenPair.getUser().getDisplayName()
        );
        return ResponseEntity.ok(response);
    }

    @PostMapping("/logout")
    public ResponseEntity<?> logout(@Valid @RequestBody RefreshTokenRequest request) {
        refreshTokenService.revokeSession(request.getRefreshToken());
        return ResponseEntity.ok(Map.of("message", "Logged out successfully"));
    }

    @PostMapping("/logout-all")
    public ResponseEntity<?> logoutAll() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || "anonymousUser".equals(auth.getPrincipal())) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Not authenticated"));
        }
        userRepository.findByEmail(auth.getName()).ifPresent(u -> {
            refreshTokenService.revokeAllForUser(u.getId());
        });
        return ResponseEntity.ok(Map.of("message", "Logged out from all devices"));
    }
}
