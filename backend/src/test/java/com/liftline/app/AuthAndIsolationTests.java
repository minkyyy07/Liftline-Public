package com.liftline.app;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.liftline.app.dto.AuthRequest;
import com.liftline.app.entity.User;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.security.JwtService;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthAndIsolationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private JwtService jwtService;

    @Autowired
    private ObjectMapper objectMapper;

    @BeforeEach
    void cleanUp() {
        userRepository.deleteAll();
    }

    @Test
    @DisplayName("Registration succeeds with valid payload and hashes password")
    void registerShouldSucceedWithValidPayload() throws Exception {
        AuthRequest request = new AuthRequest();
        request.setEmail("valid.user@example.com");
        request.setPassword("strongPassword123");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("User registered successfully"));

        User user = userRepository.findByEmail("valid.user@example.com").orElse(null);
        assertThat(user).isNotNull();
        assertThat(passwordEncoder.matches("strongPassword123", user.getPasswordHash())).isTrue();
        assertThat(user.getPasswordHash()).isNotEqualTo("strongPassword123");
    }

    @Test
    @DisplayName("Login succeeds with valid credentials and returns verifiable JWT")
    void loginShouldSucceedAndReturnValidJwt() throws Exception {
        String email = "login.test@example.com";
        String rawPassword = "password123";

        User user = new User(email, passwordEncoder.encode(rawPassword));
        user = userRepository.save(user);

        AuthRequest request = new AuthRequest();
        request.setEmail(email);
        request.setPassword(rawPassword);

        MvcResult result = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").isString())
                .andExpect(jsonPath("$.email").value(email))
                .andReturn();

        JsonNode responseNode = objectMapper.readTree(result.getResponse().getContentAsString());
        String token = responseNode.get("token").asText();

        assertThat(token).isNotBlank();
        UUID parsedId = jwtService.parseUserId(token);
        assertThat(parsedId).isEqualTo(user.getId());
        assertThat(jwtService.parseEmail(token)).isEqualTo(email);
    }

    @Test
    @DisplayName("Registration rejects duplicate email even with different casing")
    void duplicateEmailRegistrationShouldFail() throws Exception {
        AuthRequest first = new AuthRequest();
        first.setEmail("duplicate@example.com");
        first.setPassword("secret12345");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(first)))
                .andExpect(status().isOk());

        AuthRequest second = new AuthRequest();
        second.setEmail("DUPLICATE@EXAMPLE.COM");
        second.setPassword("anotherPassword");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(second)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Email already registered"));
    }

    @Test
    @DisplayName("Registration rejects invalid payloads (malformed email, short password, empty fields)")
    void registerWithInvalidDataShouldReturnBadRequest() throws Exception {
        // Malformed email
        AuthRequest badEmail = new AuthRequest();
        badEmail.setEmail("not-a-valid-email");
        badEmail.setPassword("validPass123");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(badEmail)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Validation failed"))
                .andExpect(jsonPath("$.details.email").exists());

        // Password shorter than 8 chars
        AuthRequest shortPassword = new AuthRequest();
        shortPassword.setEmail("valid@example.com");
        shortPassword.setPassword("short");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(shortPassword)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Validation failed"))
                .andExpect(jsonPath("$.details.password").exists());

        // Blank fields
        AuthRequest emptyRequest = new AuthRequest();
        emptyRequest.setEmail("");
        emptyRequest.setPassword("");

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(emptyRequest)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Validation failed"));
    }

    @Test
    @DisplayName("Password boundary tests for 8 chars min, 72 bytes max (BCrypt limit), and multi-byte UTF-8")
    void passwordBoundaryTests() throws Exception {
        // 7 characters: rejected (too short)
        AuthRequest tooShort = new AuthRequest();
        tooShort.setEmail("short7@example.com");
        tooShort.setPassword("1234567");
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(tooShort)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details.password").value("Password must be at least 8 characters"));

        // 8 characters: accepted (min boundary)
        AuthRequest minBoundary = new AuthRequest();
        minBoundary.setEmail("min8@example.com");
        minBoundary.setPassword("12345678");
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(minBoundary)))
                .andExpect(status().isOk());

        // 72 ASCII characters = 72 bytes: accepted (max boundary)
        String max72Ascii = "A".repeat(72);
        AuthRequest maxBoundary = new AuthRequest();
        maxBoundary.setEmail("max72@example.com");
        maxBoundary.setPassword(max72Ascii);
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(maxBoundary)))
                .andExpect(status().isOk());

        // 73 ASCII characters = 73 bytes: rejected (exceeds BCrypt 72-byte limit)
        String tooLong73Ascii = "A".repeat(73);
        AuthRequest overBoundary = new AuthRequest();
        overBoundary.setEmail("over73@example.com");
        overBoundary.setPassword(tooLong73Ascii);
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(overBoundary)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details.password").value("Password length in UTF-8 must not exceed 72 bytes (BCrypt limit)"));

        // Multi-byte UTF-8: Euro sign '€' is 3 bytes in UTF-8. 25 chars = 75 bytes (exceeds 72 bytes)
        String multiByteTooLong = "€".repeat(25);
        AuthRequest utf8Over = new AuthRequest();
        utf8Over.setEmail("utf8over@example.com");
        utf8Over.setPassword(multiByteTooLong);
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(utf8Over)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details.password").value("Password length in UTF-8 must not exceed 72 bytes (BCrypt limit)"));

        // Multi-byte UTF-8 within limit: 20 Euro signs = 60 bytes: accepted
        String multiByteValid = "€".repeat(20);
        AuthRequest utf8Valid = new AuthRequest();
        utf8Valid.setEmail("utf8valid@example.com");
        utf8Valid.setPassword(multiByteValid);
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(utf8Valid)))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Concurrent registration race condition protection returns 400 instead of 500")
    void concurrentRegistrationReturns400Without500() throws Exception {
        int threadCount = 10;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch readyLatch = new CountDownLatch(threadCount);
        CountDownLatch startLatch = new CountDownLatch(1);

        String raceEmail = "race_condition@example.com";
        AuthRequest request = new AuthRequest();
        request.setEmail(raceEmail);
        request.setPassword("strongPassword123");
        String payload = objectMapper.writeValueAsString(request);

        List<Integer> statusCodes = Collections.synchronizedList(new ArrayList<>());
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            futures.add(executor.submit(() -> {
                readyLatch.countDown();
                try {
                    startLatch.await();
                    MvcResult res = mockMvc.perform(post("/api/auth/register")
                                    .contentType(MediaType.APPLICATION_JSON)
                                    .content(payload))
                            .andReturn();
                    statusCodes.add(res.getResponse().getStatus());
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            }));
        }

        readyLatch.await(5, TimeUnit.SECONDS);
        startLatch.countDown(); // Trigger all threads simultaneously

        for (Future<?> f : futures) {
            f.get(10, TimeUnit.SECONDS);
        }
        executor.shutdown();

        // Exactly one thread succeeded (HTTP 200)
        long successCount = statusCodes.stream().filter(s -> s == 200).count();
        assertThat(successCount).isEqualTo(1);

        // Remaining threads failed with HTTP 400 Bad Request
        long badRequestCount = statusCodes.stream().filter(s -> s == 400).count();
        assertThat(badRequestCount).isEqualTo(threadCount - 1);

        // No 500 Internal Server Errors occurred
        long internalErrorCount = statusCodes.stream().filter(s -> s == 500).count();
        assertThat(internalErrorCount).isZero();

        // Exactly one user persisted in the database
        assertThat(userRepository.count()).isEqualTo(1);
        assertThat(userRepository.findByEmail(raceEmail)).isPresent();
    }

    @Test
    @DisplayName("Login rejects incorrect password")
    void loginWithWrongPasswordShouldFail() throws Exception {
        User user = new User("wrongpass@example.com", passwordEncoder.encode("correctPassword"));
        userRepository.save(user);

        AuthRequest badPassRequest = new AuthRequest();
        badPassRequest.setEmail("wrongpass@example.com");
        badPassRequest.setPassword("incorrectPassword");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(badPassRequest)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").value("Invalid credentials"));
    }

    @Test
    @DisplayName("Login rejects non-existent user")
    void loginWithNonExistentUserShouldFail() throws Exception {
        AuthRequest unknownUser = new AuthRequest();
        unknownUser.setEmail("nonexistent@example.com");
        unknownUser.setPassword("somePassword");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(unknownUser)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").value("Invalid credentials"));
    }

    @Test
    @DisplayName("JWT lifecycle: generation, claim extraction, and tamper detection")
    void jwtLifecycleAndTamperVerification() {
        User user = new User("jwt.verify@example.com", passwordEncoder.encode("secret12345"));
        user = userRepository.save(user);

        String token = jwtService.generateToken(user);
        assertThat(token).isNotBlank();

        UUID parsedId = jwtService.parseUserId(token);
        assertThat(parsedId).isEqualTo(user.getId());
        assertThat(jwtService.parseEmail(token)).isEqualTo(user.getEmail());

        // Tampered token must fail validation
        String tamperedToken = token.substring(0, token.length() - 5) + "abcde";
        assertThatThrownBy(() -> jwtService.parseUserId(tamperedToken))
                .isInstanceOf(Exception.class);
    }

    @Test
    @DisplayName("Protected endpoint rejects request without valid token and allows authenticated token")
    void protectedEndpointsRequireValidJwt() throws Exception {
        // Request without token to secured endpoint should be rejected (403 Forbidden by default in Spring Security)
        mockMvc.perform(get("/api/workouts"))
                .andExpect(status().isForbidden());

        // Request with invalid token format should also be rejected
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer invalid-jwt-token"))
                .andExpect(status().isForbidden());

        // Request with valid user token should pass authentication filter
        User user = new User("authed@example.com", passwordEncoder.encode("password123"));
        user = userRepository.save(user);
        String token = jwtService.generateToken(user);

        // When authenticated, endpoint responds (not 401/403)
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Complete end-to-end registration and login flow via MockMvc with JWT verification")
    void fullRegistrationAndLoginFlowViaMockMvc() throws Exception {
        String email = "e2e.flow@example.com";
        String password = "securePassword123";

        // 1. Register via MockMvc
        AuthRequest registerRequest = new AuthRequest();
        registerRequest.setEmail(email);
        registerRequest.setPassword(password);

        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(registerRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("User registered successfully"));

        // 2. Login via MockMvc with registered credentials
        AuthRequest loginRequest = new AuthRequest();
        loginRequest.setEmail(email);
        loginRequest.setPassword(password);

        MvcResult loginResult = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(loginRequest)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").isString())
                .andExpect(jsonPath("$.email").value(email))
                .andReturn();

        // 3. Extract and verify JWT
        JsonNode responseNode = objectMapper.readTree(loginResult.getResponse().getContentAsString());
        String token = responseNode.get("token").asText();
        assertThat(token).isNotBlank();

        UUID userId = jwtService.parseUserId(token);
        assertThat(userId).isNotNull();
        assertThat(jwtService.parseEmail(token)).isEqualTo(email);

        User registeredUser = userRepository.findByEmail(email).orElse(null);
        assertThat(registeredUser).isNotNull();
        assertThat(registeredUser.getId()).isEqualTo(userId);

        // 4. Access protected endpoint using the extracted JWT
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Login rejects invalid payloads (malformed email, blank password, malformed JSON)")
    void loginWithInvalidDataShouldReturnBadRequest() throws Exception {
        // Malformed email
        AuthRequest badEmail = new AuthRequest();
        badEmail.setEmail("not-a-valid-email");
        badEmail.setPassword("validPass123");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(badEmail)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Validation failed"))
                .andExpect(jsonPath("$.details.email").exists());

        // Blank password
        AuthRequest emptyPassword = new AuthRequest();
        emptyPassword.setEmail("valid@example.com");
        emptyPassword.setPassword("");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(emptyPassword)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Validation failed"))
                .andExpect(jsonPath("$.details.password").exists());

        // Malformed JSON syntax
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{invalid-json-body}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("JWT parser rejects tokens signed with untrusted secret key")
    void jwtVerificationRejectsUntrustedKey() {
        User user = new User("untrusted@example.com", passwordEncoder.encode("secret12345"));
        user = userRepository.save(user);

        // Create token with different valid 32-byte secret
        SecretKey differentKey = Keys.hmacShaKeyFor(
                "different-secret-key-that-is-at-least-32-bytes!".getBytes(StandardCharsets.UTF_8)
        );

        String untrustedToken = Jwts.builder()
                .subject(user.getId().toString())
                .claim("email", user.getEmail())
                .signWith(differentKey)
                .compact();

        assertThatThrownBy(() -> jwtService.parseUserId(untrustedToken))
                .isInstanceOf(Exception.class);
    }
}
