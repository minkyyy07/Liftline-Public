package com.liftline.app;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.liftline.app.dto.AuthRequest;
import com.liftline.app.entity.User;
import com.liftline.app.repository.RefreshSessionRepository;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.repository.WorkoutRepository;
import com.liftline.app.security.AuthRateLimiter;
import org.junit.jupiter.api.AfterEach;
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

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Contract tests for the Flutter <-> backend workout sync payloads.
 * Payloads are built as raw JSON maps (what the Flutter client actually sends),
 * so the tests also cover old payloads that omit the newer fields.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class WorkoutSyncContractTests {

    private static final String PASSWORD = "password123";

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
    }

    /** Shared in-memory H2: leave no workouts/users behind for other test classes. */
    @AfterEach
    void tearDown() {
        workoutRepository.deleteAll();
        refreshSessionRepository.deleteAll();
        userRepository.deleteAll();
    }

    // ---------- helpers ----------

    private String login(String email) throws Exception {
        if (userRepository.findByEmail(email).isEmpty()) {
            userRepository.save(new User(email, passwordEncoder.encode(PASSWORD)));
        }
        AuthRequest req = new AuthRequest();
        req.setEmail(email);
        req.setPassword(PASSWORD);
        MvcResult res = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isOk())
                .andReturn();
        return objectMapper.readTree(res.getResponse().getContentAsString()).get("accessToken").asText();
    }

    private JsonNode send(String method, String url, String token, Object body, int expectedStatus) throws Exception {
        var builder = switch (method) {
            case "POST" -> post(url);
            case "PUT" -> put(url);
            case "GET" -> get(url);
            default -> throw new IllegalArgumentException(method);
        };
        builder.header("Authorization", "Bearer " + token);
        if (body != null) {
            builder.contentType(MediaType.APPLICATION_JSON).content(objectMapper.writeValueAsString(body));
        }
        MvcResult res = mockMvc.perform(builder).andExpect(status().is(expectedStatus)).andReturn();
        String content = res.getResponse().getContentAsString();
        return content.isBlank() ? null : objectMapper.readTree(content);
    }

    private static Map<String, Object> set(int number, double kg, int reps, boolean completed, Integer rir,
                                           String completedAt) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("id", UUID.randomUUID().toString());
        s.put("setNumber", number);
        s.put("weightKg", kg);
        s.put("reps", reps);
        s.put("completed", completed);
        s.put("setType", "work");
        s.put("notes", null);
        s.put("rir", rir);
        s.put("completedAtUtc", completedAt);
        return s;
    }

    private static Map<String, Object> exercise(String id, String name, int sortOrder, String refId, List<Map<String, Object>> sets) {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("id", id);
        e.put("exerciseName", name);
        e.put("sortOrder", sortOrder);
        e.put("exerciseRefId", refId);
        e.put("notes", "tempo 3-1-1");
        e.put("planSets", 4);
        e.put("planRepMin", 6);
        e.put("planRepMax", 10);
        e.put("planRir", 2);
        e.put("planRestSec", 120);
        e.put("sets", sets);
        return e;
    }

    private static Map<String, Object> workoutPayload(String id, String title, String status,
                                                     String startedAt, String finishedAt,
                                                     List<Map<String, Object>> exercises) {
        Map<String, Object> w = new LinkedHashMap<>();
        w.put("id", id);
        w.put("title", title);
        w.put("workoutDate", "2026-11-04");
        w.put("durationMinutes", null);
        w.put("notes", "felt good");
        w.put("status", status);
        w.put("startedAtUtc", startedAt);
        w.put("finishedAtUtc", finishedAt);
        w.put("exercises", exercises);
        return w;
    }

    private static Map<String, Object> workoutCreatePayload(String id, String title, String status,
                                                           String startedAt, String finishedAt,
                                                           List<Map<String, Object>> exercises) {
        return workoutPayload(id, title, status, startedAt, finishedAt, exercises);
    }

    // ---------- tests ----------

    @Test
    @DisplayName("planned, active and finished workouts round-trip all lifecycle, plan, RIR and catalogue fields")
    void lifecycleAndPlanFieldsRoundTrip() throws Exception {
        String token = login("roundtrip.contract@example.com");
        String refId = UUID.randomUUID().toString();

        String plannedId = UUID.randomUUID().toString();
        send("POST", "/api/workouts", token,
                workoutCreatePayload(plannedId, "Planned Push", "planned", null, null,
                        List.of(exercise(UUID.randomUUID().toString(), "Bench Press", 1, refId, List.of()))),
                201);

        String activeId = UUID.randomUUID().toString();
        String activeStart = "2026-11-04T09:00:00.123Z";
        send("POST", "/api/workouts", token,
                workoutCreatePayload(activeId, "Active Pull", "active", activeStart, null,
                        List.of(exercise(UUID.randomUUID().toString(), "Row", 1, null,
                                List.of(set(1, 80.5, 8, true, 1, "2026-11-04T09:05:00.000Z"),
                                        set(2, 80.5, 8, false, null, null))))),
                201);

        String finishedId = UUID.randomUUID().toString();
        send("POST", "/api/workouts", token,
                workoutCreatePayload(finishedId, "Finished Legs", "finished", "2026-11-03T18:00:00.000Z",
                        "2026-11-03T19:10:00.000Z", List.of()),
                201);

        JsonNode planned = send("GET", "/api/workouts/" + plannedId, token, null, 200);
        assertThat(planned.get("status").asText()).isEqualTo("planned");
        assertThat(planned.get("startedAtUtc").isNull()).isTrue();
        JsonNode plannedEx = planned.get("exercises").get(0);
        assertThat(plannedEx.get("exerciseRefId").asText()).isEqualTo(refId);
        assertThat(plannedEx.get("planSets").asInt()).isEqualTo(4);
        assertThat(plannedEx.get("planRepMin").asInt()).isEqualTo(6);
        assertThat(plannedEx.get("planRepMax").asInt()).isEqualTo(10);
        assertThat(plannedEx.get("planRir").asInt()).isEqualTo(2);
        assertThat(plannedEx.get("planRestSec").asInt()).isEqualTo(120);
        assertThat(plannedEx.get("notes").asText()).isEqualTo("tempo 3-1-1");

        JsonNode active = send("GET", "/api/workouts/" + activeId, token, null, 200);
        assertThat(active.get("status").asText()).isEqualTo("active");
        assertThat(active.get("startedAtUtc").asText()).isEqualTo(activeStart);
        assertThat(active.get("finishedAtUtc").isNull()).isTrue();
        JsonNode firstSet = active.get("exercises").get(0).get("sets").get(0);
        assertThat(firstSet.get("rir").asInt()).isEqualTo(1);
        assertThat(firstSet.get("completedAtUtc").asText()).isEqualTo("2026-11-04T09:05:00Z");
        assertThat(active.get("exercises").get(0).get("sets").get(1).get("completedAtUtc").isNull()).isTrue();

        JsonNode finished = send("GET", "/api/workouts/" + finishedId, token, null, 200);
        assertThat(finished.get("status").asText()).isEqualTo("finished");
        assertThat(finished.get("startedAtUtc").asText()).isEqualTo("2026-11-03T18:00:00Z");
        assertThat(finished.get("finishedAtUtc").asText()).isEqualTo("2026-11-03T19:10:00Z");
    }

    @Test
    @DisplayName("PUT with the same exercise/set ids updates rows in place and keeps exercise and set order")
    void putWithSameIdsKeepsOrderAndUpdatesInPlace() throws Exception {
        String token = login("order.contract@example.com");
        String workoutId = UUID.randomUUID().toString();
        String exA = UUID.randomUUID().toString();
        String exB = UUID.randomUUID().toString();
        String setA2 = UUID.randomUUID().toString();
        String setA1 = UUID.randomUUID().toString();

        // Payload deliberately lists items out of order: the server must sort them.
        Map<String, Object> s2 = set(2, 60, 10, true, 2, null);
        s2.put("id", setA2);
        Map<String, Object> s1 = set(1, 55, 12, true, 3, null);
        s1.put("id", setA1);
        Map<String, Object> exerciseB = exercise(exB, "Squat", 2, null, List.of());
        Map<String, Object> exerciseA = exercise(exA, "Deadlift", 1, null, List.of(s2, s1));

        send("POST", "/api/workouts", token,
                workoutCreatePayload(workoutId, "Order Test", "active", "2026-11-04T10:00:00.000Z", null,
                        List.of(exerciseB, exerciseA)),
                201);

        // Second upload (same ids, changed weight) must not recreate or reorder anything.
        s1.put("weightKg", 57.5);
        JsonNode updated = send("PUT", "/api/workouts/" + workoutId, token,
                updatePayload("Order Test", "active", "2026-11-04T10:00:00.000Z", null,
                        List.of(exerciseB, exerciseA), null),
                200);

        JsonNode exs = updated.get("exercises");
        assertThat(exs.get(0).get("id").asText()).isEqualTo(exA);
        assertThat(exs.get(0).get("exerciseName").asText()).isEqualTo("Deadlift");
        assertThat(exs.get(1).get("id").asText()).isEqualTo(exB);
        JsonNode sets = exs.get(0).get("sets");
        assertThat(sets.get(0).get("id").asText()).isEqualTo(setA1);
        assertThat(sets.get(0).get("setNumber").asInt()).isEqualTo(1);
        assertThat(sets.get(0).get("weightKg").asDouble()).isEqualTo(57.5);
        assertThat(sets.get(1).get("id").asText()).isEqualTo(setA2);
        assertThat(sets.get(1).get("rir").asInt()).isEqualTo(2);

        JsonNode reread = send("GET", "/api/workouts/" + workoutId, token, null, 200);
        assertThat(reread.get("exercises").get(0).get("id").asText()).isEqualTo(exA);
        assertThat(reread.get("exercises").get(0).get("sets").size()).isEqualTo(2);
    }

    @Test
    @DisplayName("Legacy PUT without the new fields keeps stored status, timestamps, plan, RIR and catalogue ref")
    void legacyPutWithoutNewFieldsKeepsStoredValues() throws Exception {
        String token = login("legacy.put@example.com");
        String workoutId = UUID.randomUUID().toString();
        String exId = UUID.randomUUID().toString();
        String setId = UUID.randomUUID().toString();
        String refId = UUID.randomUUID().toString();

        Map<String, Object> set = set(1, 100, 5, true, 1, "2026-11-04T10:05:00.000Z");
        set.put("id", setId);
        Map<String, Object> exercise = exercise(exId, "Bench", 1, refId, List.of(set));
        send("POST", "/api/workouts", token,
                workoutCreatePayload(workoutId, "Keep Me", "active", "2026-11-04T10:00:00.000Z", null,
                        List.of(exercise)),
                201);

        // An old client (before this contract) sends only the legacy fields.
        Map<String, Object> legacyEx = new LinkedHashMap<>();
        legacyEx.put("id", exId);
        legacyEx.put("exerciseName", "Bench");
        legacyEx.put("sortOrder", 1);
        Map<String, Object> legacySet = new LinkedHashMap<>();
        legacySet.put("id", setId);
        legacySet.put("setNumber", 1);
        legacySet.put("weightKg", 102.5);
        legacySet.put("reps", 5);
        legacySet.put("completed", true);
        legacySet.put("setType", "work");
        legacyEx.put("sets", List.of(legacySet));
        Map<String, Object> legacy = new LinkedHashMap<>();
        legacy.put("title", "Keep Me (edited on old client)");
        legacy.put("workoutDate", "2026-11-04");
        legacy.put("durationMinutes", 40);
        legacy.put("notes", null);
        legacy.put("version", 0);
        legacy.put("exercises", List.of(legacyEx));

        JsonNode res = send("PUT", "/api/workouts/" + workoutId, token, legacy, 200);
        assertThat(res.get("title").asText()).isEqualTo("Keep Me (edited on old client)");
        assertThat(res.get("status").asText()).isEqualTo("active");
        assertThat(res.get("startedAtUtc").asText()).isEqualTo("2026-11-04T10:00:00Z");

        JsonNode ex = send("GET", "/api/workouts/" + workoutId, token, null, 200).get("exercises").get(0);
        assertThat(ex.get("exerciseRefId").asText()).isEqualTo(refId);
        assertThat(ex.get("planSets").asInt()).isEqualTo(4);
        assertThat(ex.get("planRir").asInt()).isEqualTo(2);
        assertThat(ex.get("notes").asText()).isEqualTo("tempo 3-1-1");
        JsonNode s = ex.get("sets").get(0);
        assertThat(s.get("weightKg").asDouble()).isEqualTo(102.5);
        assertThat(s.get("rir").asInt()).isEqualTo(1);
        assertThat(s.get("completedAtUtc").asText()).isEqualTo("2026-11-04T10:05:00Z");
    }

    @Test
    @DisplayName("Explicit null clears an optional field, while a null status (NOT NULL) is ignored")
    void explicitNullClearsOptionalFieldsButNotStatus() throws Exception {
        String token = login("null.contract@example.com");
        String workoutId = UUID.randomUUID().toString();
        String exId = UUID.randomUUID().toString();
        Map<String, Object> exercise = exercise(exId, "Row", 1, null, List.of());
        send("POST", "/api/workouts", token,
                workoutCreatePayload(workoutId, "Nulls", "planned", null, null, List.of(exercise)),
                201);

        Map<String, Object> cleared = exercise(exId, "Row", 1, null, List.of());
        cleared.put("planRir", null);
        Map<String, Object> body = updatePayload("Nulls", null, null, null, List.of(cleared), null);
        body.put("status", null);
        JsonNode res = send("PUT", "/api/workouts/" + workoutId, token, body, 200);

        assertThat(res.get("status").asText()).isEqualTo("planned");
        JsonNode ex = res.get("exercises").get(0);
        assertThat(ex.get("planRir").isNull()).isTrue();
        assertThat(ex.get("planSets").asInt()).isEqualTo(4);
    }

    @Test
    @DisplayName("Legacy POST without status is stored as finished (historical workouts)")
    void legacyPostWithoutStatusIsFinished() throws Exception {
        String token = login("legacy.post@example.com");
        String workoutId = UUID.randomUUID().toString();
        Map<String, Object> legacy = new LinkedHashMap<>();
        legacy.put("id", workoutId);
        legacy.put("title", "Old client");
        legacy.put("workoutDate", "2026-10-01");
        legacy.put("durationMinutes", 30);
        legacy.put("notes", null);
        legacy.put("exercises", List.of());
        JsonNode res = send("POST", "/api/workouts", token, legacy, 201);
        assertThat(res.get("status").asText()).isEqualTo("finished");
        assertThat(res.get("startedAtUtc").isNull()).isTrue();
    }

    @Test
    @DisplayName("Paging across equal dates returns every workout exactly once")
    void pagingWithEqualDatesIsComplete() throws Exception {
        String token = login("paging.contract@example.com");
        Set<String> created = new java.util.HashSet<>();
        for (int i = 0; i < 5; i++) {
            String id = UUID.randomUUID().toString();
            created.add(id);
            send("POST", "/api/workouts", token,
                    workoutCreatePayload(id, "Same day " + i, "planned", null, null, List.of()),
                    201);
        }

        Set<String> seen = new java.util.HashSet<>();
        int page = 0;
        while (true) {
            JsonNode list = send("GET", "/api/workouts?page=" + page + "&size=2", token, null, 200);
            for (JsonNode w : list) {
                assertThat(seen.add(w.get("id").asText())).as("duplicate across pages").isTrue();
            }
            if (list.size() < 2) break;
            page++;
        }
        assertThat(seen).isEqualTo(created);
    }

    @Test
    @DisplayName("PUT response carries the stored revision, so the next upload from the same device is not a conflict")
    void putResponseVersionIsTheStoredRevision() throws Exception {
        String token = login("revision.contract@example.com");
        String workoutId = UUID.randomUUID().toString();
        JsonNode created = send("POST", "/api/workouts", token,
                workoutCreatePayload(workoutId, "Rev 0", "planned", null, null, List.of()), 201);
        long v0 = created.get("version").asLong();

        JsonNode first = send("PUT", "/api/workouts/" + workoutId, token,
                updatePayload("Rev 1", "planned", null, null, List.of(), v0), 200);
        long v1 = first.get("version").asLong();
        assertThat(v1).isEqualTo(v0 + 1);

        // Queued second edit from the same device, sent with the revision it just received.
        JsonNode second = send("PUT", "/api/workouts/" + workoutId, token,
                updatePayload("Rev 2", "active", "2026-11-04T10:00:00.000Z", null, List.of(), v1), 200);
        assertThat(second.get("version").asLong()).isEqualTo(v1 + 1);
        assertThat(send("GET", "/api/workouts/" + workoutId, token, null, 200).get("version").asLong())
                .isEqualTo(v1 + 1);
    }

    @Test
    @DisplayName("A client UUID that belongs to another account is never taken over")
    void foreignClientIdIsNotTakenOver() throws Exception {
        String ownerToken = login("owner.iso@example.com");
        String intruderToken = login("intruder.iso@example.com");
        String workoutId = UUID.randomUUID().toString();

        send("POST", "/api/workouts", ownerToken,
                workoutCreatePayload(workoutId, "Owner Secret", "finished", null, null, List.of()),
                201);

        send("POST", "/api/workouts", intruderToken,
                workoutCreatePayload(workoutId, "Hijacked", "planned", null, null, List.of()),
                403);

        JsonNode owner = send("GET", "/api/workouts/" + workoutId, ownerToken, null, 200);
        assertThat(owner.get("title").asText()).isEqualTo("Owner Secret");
        JsonNode intruderList = send("GET", "/api/workouts", intruderToken, null, 200);
        assertThat(intruderList.size()).isZero();
    }

    private static Map<String, Object> updatePayload(String title, String status, String startedAt,
                                                     String finishedAt, List<Map<String, Object>> exercises,
                                                     Long version) {
        Map<String, Object> body = new HashMap<>();
        body.put("title", title);
        body.put("workoutDate", "2026-11-04");
        body.put("durationMinutes", null);
        body.put("notes", null);
        body.put("status", status);
        body.put("startedAtUtc", startedAt);
        body.put("finishedAtUtc", finishedAt);
        body.put("exercises", exercises);
        if (version != null) body.put("version", version);
        return body;
    }
}
