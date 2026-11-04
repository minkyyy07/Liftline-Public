package com.liftline.app;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.liftline.app.dto.AuthRequest;
import com.liftline.app.dto.ChangePasswordRequest;
import com.liftline.app.dto.CreateWorkoutRequest;
import com.liftline.app.dto.RefreshTokenRequest;
import com.liftline.app.dto.SetEntryDto;
import com.liftline.app.dto.UpdateProfileRequest;
import com.liftline.app.dto.UpdateWorkoutRequest;
import com.liftline.app.dto.WorkoutExerciseDto;
import com.liftline.app.entity.User;
import com.liftline.app.repository.RefreshSessionRepository;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.repository.WorkoutRepository;
import com.liftline.app.security.AuthRateLimiter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthSessionAndWorkoutApiTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private RefreshSessionRepository refreshSessionRepository;

    @Autowired
    private WorkoutRepository workoutRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private AuthRateLimiter authRateLimiter;

    @BeforeEach
    void setUp() {
        authRateLimiter.reset();
        workoutRepository.deleteAll();
        refreshSessionRepository.deleteAll();
        userRepository.deleteAll();
    }

    private JsonNode loginUser(String email, String password) throws Exception {
        AuthRequest req = new AuthRequest();
        req.setEmail(email);
        req.setPassword(password);

        MvcResult result = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isOk())
                .andReturn();

        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    @Test
    @DisplayName("Login issues rotating refresh token; refresh endpoint returns new token pair")
    void refreshTokenRotationSuccess() throws Exception {
        String email = "refresh.user@example.com";
        String password = "validPassword123";
        userRepository.save(new User(email, passwordEncoder.encode(password)));

        JsonNode loginResponse = loginUser(email, password);
        String initialAccess = loginResponse.get("accessToken").asText();
        String initialRefresh = loginResponse.get("refreshToken").asText();

        assertThat(initialAccess).isNotBlank();
        assertThat(initialRefresh).isNotBlank();

        // Call /api/auth/refresh with the refresh token
        RefreshTokenRequest refreshReq = new RefreshTokenRequest(initialRefresh);
        MvcResult refreshResult = mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(refreshReq)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isString())
                .andExpect(jsonPath("$.refreshToken").isString())
                .andReturn();

        JsonNode refreshed = objectMapper.readTree(refreshResult.getResponse().getContentAsString());
        String newAccess = refreshed.get("accessToken").asText();
        String newRefresh = refreshed.get("refreshToken").asText();

        assertThat(newRefresh).isNotEqualTo(initialRefresh);
        assertThat(newAccess).isNotBlank();

        // Verify the new access token can query secured endpoints
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer " + newAccess))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Refresh token reuse detection revokes entire token family")
    void refreshTokenReuseDetectionRevokesFamily() throws Exception {
        String email = "reuse.detection@example.com";
        String password = "securePassword123";
        userRepository.save(new User(email, passwordEncoder.encode(password)));

        JsonNode loginResponse = loginUser(email, password);
        String initialRefresh = loginResponse.get("refreshToken").asText();

        // 1st legitimate rotation: replaces initialRefresh with secondRefresh
        RefreshTokenRequest refreshReq1 = new RefreshTokenRequest(initialRefresh);
        MvcResult res1 = mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(refreshReq1)))
                .andExpect(status().isOk())
                .andReturn();

        String secondRefresh = objectMapper.readTree(res1.getResponse().getContentAsString()).get("refreshToken").asText();

        // 2nd legitimate rotation: replaces secondRefresh with thirdRefresh
        RefreshTokenRequest refreshReq2 = new RefreshTokenRequest(secondRefresh);
        MvcResult res2 = mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(refreshReq2)))
                .andExpect(status().isOk())
                .andReturn();

        String thirdRefresh = objectMapper.readTree(res2.getResponse().getContentAsString()).get("refreshToken").asText();

        // Attacker / bad client tries to reuse initialRefresh (already revoked!)
        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(initialRefresh))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").value("Token reuse detected. All sessions in this chain have been revoked."));

        // Now, because of token reuse detection, even thirdRefresh (the newest valid one in family) MUST be revoked!
        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(thirdRefresh))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Logout revokes current refresh session")
    void logoutRevokesSession() throws Exception {
        String email = "logout.test@example.com";
        String password = "password123";
        userRepository.save(new User(email, passwordEncoder.encode(password)));

        JsonNode login = loginUser(email, password);
        String refresh = login.get("refreshToken").asText();

        // Logout
        mockMvc.perform(post("/api/auth/logout")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(refresh))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Logged out successfully"));

        // Attempting to refresh with logged-out token fails
        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(refresh))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Logout all devices revokes all sessions of user")
    void logoutAllRevokesAllSessions() throws Exception {
        String email = "multi.session@example.com";
        String password = "password123";
        userRepository.save(new User(email, passwordEncoder.encode(password)));

        // Login on device 1
        JsonNode session1 = loginUser(email, password);
        String token1 = session1.get("accessToken").asText();
        String refresh1 = session1.get("refreshToken").asText();

        // Login on device 2
        JsonNode session2 = loginUser(email, password);
        String refresh2 = session2.get("refreshToken").asText();

        // Device 1 calls /api/auth/logout-all
        mockMvc.perform(post("/api/auth/logout-all")
                        .header("Authorization", "Bearer " + token1))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Logged out from all devices"));

        // Both refresh tokens are now revoked
        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(refresh1))))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(refresh2))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Profile GET and PATCH updates displayName without altering email")
    void profileGetAndPatch() throws Exception {
        String email = "profile.user@example.com";
        String password = "password123";
        User user = new User(email, passwordEncoder.encode(password), "Initial Name");
        user = userRepository.save(user);

        JsonNode login = loginUser(email, password);
        String token = login.get("accessToken").asText();

        // 1. GET profile
        mockMvc.perform(get("/api/user/profile")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value(email))
                .andExpect(jsonPath("$.displayName").value("Initial Name"));

        // 2. PATCH profile
        UpdateProfileRequest updateReq = new UpdateProfileRequest("Updated Coach");
        mockMvc.perform(patch("/api/user/profile")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updateReq)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("Updated Coach"))
                .andExpect(jsonPath("$.email").value(email));

        User reloaded = userRepository.findById(user.getId()).orElseThrow();
        assertThat(reloaded.getDisplayName()).isEqualTo("Updated Coach");
        assertThat(reloaded.getEmail()).isEqualTo(email);
    }

    @Test
    @DisplayName("Password change requires correct current password and revokes all refresh sessions")
    void changePasswordFlow() throws Exception {
        String email = "passchange@example.com";
        String oldPass = "oldStrongPassword1";
        String newPass = "newStrongPassword2";
        userRepository.save(new User(email, passwordEncoder.encode(oldPass)));

        JsonNode login = loginUser(email, oldPass);
        String token = login.get("accessToken").asText();
        String refresh = login.get("refreshToken").asText();

        // Wrong current password fails with 400
        ChangePasswordRequest wrongReq = new ChangePasswordRequest("wrongOldPassword", newPass);
        mockMvc.perform(post("/api/user/change-password")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(wrongReq)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Current password does not match"));

        // Correct password change succeeds
        ChangePasswordRequest correctReq = new ChangePasswordRequest(oldPass, newPass);
        mockMvc.perform(post("/api/user/change-password")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(correctReq)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Password changed successfully. All sessions revoked."));

        // Old refresh token is revoked
        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new RefreshTokenRequest(refresh))))
                .andExpect(status().isUnauthorized());

        // Login with old password fails
        AuthRequest oldLogin = new AuthRequest();
        oldLogin.setEmail(email);
        oldLogin.setPassword(oldPass);
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(oldLogin)))
                .andExpect(status().isUnauthorized());

        // Login with new password succeeds
        AuthRequest newLogin = new AuthRequest();
        newLogin.setEmail(email);
        newLogin.setPassword(newPass);
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(newLogin)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isString());
    }

    @Test
    @DisplayName("Workout CRUD API: create, read, update, delete with exercises, sets, and cross-account isolation")
    void workoutCrudAndIsolationApi() throws Exception {
        // Create User A and User B
        userRepository.save(new User("userA@example.com", passwordEncoder.encode("password123")));
        userRepository.save(new User("userB@example.com", passwordEncoder.encode("password123")));

        JsonNode loginA = loginUser("userA@example.com", "password123");
        String tokenA = loginA.get("accessToken").asText();

        JsonNode loginB = loginUser("userB@example.com", "password123");
        String tokenB = loginB.get("accessToken").asText();

        // 1. User A creates a workout with an exercise and 2 sets
        CreateWorkoutRequest createReq = new CreateWorkoutRequest();
        createReq.setTitle("User A Push Day");
        createReq.setWorkoutDate(LocalDate.now());
        createReq.setDurationMinutes(55);
        createReq.setNotes("Heavy bench press focus");

        WorkoutExerciseDto exercise = new WorkoutExerciseDto();
        exercise.setExerciseName("Bench Press");
        exercise.setSortOrder(1);

        SetEntryDto set1 = new SetEntryDto();
        set1.setSetNumber(1);
        set1.setWeightKg(new BigDecimal("80.00"));
        set1.setReps(10);
        set1.setCompleted(true);
        set1.setSetType("work");

        SetEntryDto set2 = new SetEntryDto();
        set2.setSetNumber(2);
        set2.setWeightKg(new BigDecimal("90.00"));
        set2.setReps(8);
        set2.setCompleted(true);
        set2.setSetType("work");

        exercise.setSets(List.of(set1, set2));
        createReq.setExercises(List.of(exercise));

        MvcResult createResult = mockMvc.perform(post("/api/workouts")
                        .header("Authorization", "Bearer " + tokenA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(createReq)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isString())
                .andExpect(jsonPath("$.title").value("User A Push Day"))
                .andExpect(jsonPath("$.exercises[0].exerciseName").value("Bench Press"))
                .andExpect(jsonPath("$.exercises[0].sets.length()").value(2))
                .andReturn();

        String workoutIdStr = objectMapper.readTree(createResult.getResponse().getContentAsString()).get("id").asText();
        UUID workoutId = UUID.fromString(workoutIdStr);

        // 2. User A reads workout list
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer " + tokenA))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].title").value("User A Push Day"));

        // 3. User B reads workout list -> User B gets EMPTY list (data isolation!)
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer " + tokenB))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));

        // 4. User B attempts to access User A's workout by ID -> rejected with 403 Forbidden
        mockMvc.perform(get("/api/workouts/" + workoutId)
                        .header("Authorization", "Bearer " + tokenB))
                .andExpect(status().isForbidden());

        // 5. User B attempts to update User A's workout -> rejected with 403 Forbidden
        UpdateWorkoutRequest hostileUpdate = new UpdateWorkoutRequest();
        hostileUpdate.setTitle("Hacked Title");
        hostileUpdate.setWorkoutDate(LocalDate.now());
        mockMvc.perform(put("/api/workouts/" + workoutId)
                        .header("Authorization", "Bearer " + tokenB)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(hostileUpdate)))
                .andExpect(status().isForbidden());

        // 6. User B attempts to delete User A's workout -> rejected with 403 Forbidden
        mockMvc.perform(delete("/api/workouts/" + workoutId)
                        .header("Authorization", "Bearer " + tokenB))
                .andExpect(status().isForbidden());

        // 7. User A updates their workout
        UpdateWorkoutRequest validUpdate = new UpdateWorkoutRequest();
        validUpdate.setTitle("User A Push Day (Heavy)");
        validUpdate.setWorkoutDate(LocalDate.now());
        validUpdate.setDurationMinutes(65);
        validUpdate.setNotes("Added incline bench");

        mockMvc.perform(put("/api/workouts/" + workoutId)
                        .header("Authorization", "Bearer " + tokenA)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(validUpdate)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title").value("User A Push Day (Heavy)"))
                .andExpect(jsonPath("$.durationMinutes").value(65));

        // 8. User A deletes their workout
        mockMvc.perform(delete("/api/workouts/" + workoutId)
                        .header("Authorization", "Bearer " + tokenA))
                .andExpect(status().isNoContent());

        // 9. Verified gone from list
        mockMvc.perform(get("/api/workouts")
                        .header("Authorization", "Bearer " + tokenA))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    @DisplayName("Rate limiter returns 429 when threshold exceeded")
    void rateLimiterReturns429() throws Exception {
        authRateLimiter.setEnabled(true);
        authRateLimiter.setMaxRequests(3);

        AuthRequest req = new AuthRequest();
        req.setEmail("rate.limit@example.com");
        req.setPassword("password123");

        // 3 requests allowed
        for (int i = 0; i < 3; i++) {
            mockMvc.perform(post("/api/auth/login")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(req)))
                    .andExpect(status().isUnauthorized()); // Invalid credentials, but NOT 429
        }

        // 4th request must be rejected with 429 Too Many Requests
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.error").value("Too many login attempts. Please try again later."));

        authRateLimiter.reset();
    }
}
