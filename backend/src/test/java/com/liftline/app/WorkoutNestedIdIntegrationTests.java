package com.liftline.app;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.liftline.app.entity.User;
import com.liftline.app.repository.RefreshSessionRepository;
import com.liftline.app.repository.SetEntryRepository;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.repository.WorkoutExerciseRepository;
import com.liftline.app.repository.WorkoutRepository;
import com.liftline.app.security.AuthRateLimiter;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.SpyBean;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@ActiveProfiles("test")
class WorkoutNestedIdIntegrationTests {
    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper mapper;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private UserRepository users;
    @Autowired private RefreshSessionRepository sessions;
    @Autowired private WorkoutRepository workouts;
    @Autowired private PasswordEncoder passwords;
    @Autowired private AuthRateLimiter rateLimiter;
    @SpyBean private WorkoutExerciseRepository exercises;
    @SpyBean private SetEntryRepository sets;
    @LocalServerPort private int port;

    private String tokenA;
    private String tokenB;
    private ObjectNode workoutA;
    private ObjectNode workoutB;
    private ObjectNode otherWorkoutB;

    @BeforeEach
    void setUp() throws Exception {
        rateLimiter.reset();
        tokenA = login("nested-a@example.com");
        tokenB = login("nested-b@example.com");
        workoutA = payload("Account A");
        workoutB = payload("Account B");
        otherWorkoutB = payload("Other B workout");
        send("POST", tokenA, workoutA, 201);
        send("POST", tokenB, workoutB, 201);
        send("POST", tokenB, otherWorkoutB, 201);
    }

    @AfterEach
    void tearDown() {
        workouts.deleteAll();
        sessions.deleteAll();
        users.deleteAll();
    }

    private String login(String email) throws Exception {
        users.save(new User(email, passwords.encode("password123")));
        MvcResult result = mvc.perform(post("/api/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(mapper.writeValueAsBytes(Map.of("email", email, "password", "password123"))))
                .andReturn();
        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        return mapper.readTree(result.getResponse().getContentAsByteArray()).get("accessToken").asText();
    }

    private ObjectNode payload(String title) {
        ObjectNode body = mapper.createObjectNode();
        body.put("id", UUID.randomUUID().toString());
        body.put("title", title);
        body.put("workoutDate", "2026-11-04");
        body.put("notes", "original notes");
        body.putArray("exercises").add(exercise("Bench", 1)).add(exercise("Squat", 2));
        return body;
    }

    private ObjectNode exercise(String name, int order) {
        ObjectNode exercise = mapper.createObjectNode();
        exercise.put("id", UUID.randomUUID().toString());
        exercise.put("exerciseName", name);
        exercise.put("sortOrder", order);
        exercise.putArray("sets").add(mapper.createObjectNode()
                .put("id", UUID.randomUUID().toString()).put("setNumber", 1)
                .put("weightKg", 60).put("reps", 8).put("completed", true));
        return exercise;
    }

    private static ObjectNode ex(ObjectNode body, int index) {
        return (ObjectNode) body.withArray("exercises").get(index);
    }

    private static ObjectNode set(ObjectNode exercise) {
        return (ObjectNode) exercise.withArray("sets").get(0);
    }

    private MvcResult request(String method, String token, ObjectNode body) throws Exception {
        var builder = "PUT".equals(method) ? put("/api/workouts/" + body.get("id").asText()) : post("/api/workouts");
        return mvc.perform(builder.header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsBytes(body))).andReturn();
    }

    private JsonNode send(String method, String token, ObjectNode body, int expected) throws Exception {
        MvcResult result = request(method, token, body);
        assertThat(result.getResponse().getStatus()).as(result.getResponse().getContentAsString()).isEqualTo(expected);
        return mapper.readTree(result.getResponse().getContentAsByteArray());
    }

    // No test transaction: every snapshot reads committed rows after the HTTP/service transaction ended.
    private JsonNode snapshot() {
        Map<String, Object> tables = new LinkedHashMap<>();
        for (String table : List.of("workout", "workout_exercise", "set_entry")) {
            tables.put(table, jdbc.queryForList("select * from " + table + " order by id"));
        }
        return mapper.valueToTree(tables);
    }

    static Stream<Object[]> invalidPayloads() {
        return Stream.of("POST", "PUT", "REPLAY").flatMap(method ->
                Stream.of("foreignExercise", "foreignSet", "sameAccountExercise", "sameAccountSet",
                        "otherExerciseSet", "duplicateExercise", "duplicateSet", "duplicateSetAcrossExercises",
                        "ambiguousExerciseSetId").map(scenario -> new Object[]{method, scenario}));
    }

    @ParameterizedTest(name = "{0}: {1} leaves all rows and revisions unchanged")
    @MethodSource("invalidPayloads")
    void invalidNestedIdsAreAtomic(String method, String scenario) throws Exception {
        ObjectNode body = "POST".equals(method) ? payload("New B workout") : workoutB.deepCopy();
        body.put("title", "Must roll back");
        ObjectNode correct = ex(body, 0);
        correct.put("exerciseName", "Must also roll back");
        set(correct).put("reps", 99);
        // Keep the first, valid change; the invalid entry is deliberately later in the payload.
        body.withArray("exercises").remove(1);
        ObjectNode invalid = exercise("Invalid", 2);
        int expected = 409;
        switch (scenario) {
            case "foreignExercise" -> invalid.put("id", ex(workoutA, 0).get("id").asText());
            case "foreignSet" -> set(invalid).put("id", set(ex(workoutA, 0)).get("id").asText());
            case "sameAccountExercise" -> invalid.put("id", ex(otherWorkoutB, 0).get("id").asText());
            case "sameAccountSet" -> set(invalid).put("id", set(ex(otherWorkoutB, 0)).get("id").asText());
            case "otherExerciseSet" -> set(invalid).put("id", set(ex(workoutB, 1)).get("id").asText());
            case "duplicateExercise" -> {
                invalid.put("id", correct.get("id").asText());
                expected = 400;
            }
            case "duplicateSet" -> {
                invalid.withArray("sets").add(set(invalid).deepCopy().put("setNumber", 2));
                expected = 400;
            }
            case "duplicateSetAcrossExercises" -> {
                set(invalid).put("id", set(correct).get("id").asText());
                expected = 400;
            }
            case "ambiguousExerciseSetId" -> {
                set(invalid).put("id", invalid.get("id").asText());
                expected = 400;
            }
            default -> throw new IllegalArgumentException(scenario);
        }
        body.withArray("exercises").add(invalid);
        JsonNode before = snapshot();
        JsonNode error = send("PUT".equals(method) ? "PUT" : "POST", tokenB, body, expected);
        assertThat(error).isEqualTo(mapper.valueToTree(Map.of("error", expected == 400
                ? "Duplicate nested workout ID" : "Workout conflict: ID already in use")));
        assertThat(snapshot()).isEqualTo(before);
    }

    @Test
    void clientIdsAndOrdinaryUpdatesPersistWithoutRecreatingChildren() throws Exception {
        ObjectNode body = payload("Offline");
        JsonNode created = send("POST", tokenB, body, 201);
        assertThat(created.at("/exercises/0/id").asText()).isEqualTo(ex(body, 0).get("id").asText());
        assertThat(created.at("/exercises/0/sets/0/id").asText()).isEqualTo(set(ex(body, 0)).get("id").asText());
        JsonNode before = snapshot();
        body.put("version", created.get("version").asLong());
        ex(body, 0).put("exerciseName", "Updated bench");
        set(ex(body, 0)).put("weightKg", 72);
        body.withArray("exercises").add(exercise("New client exercise", 3));
        JsonNode updated = send("PUT", tokenB, body, 200);
        assertThat(updated.get("version").asLong()).isEqualTo(created.get("version").asLong() + 1);
        assertThat(updated.at("/exercises/0/id")).isEqualTo(created.at("/exercises/0/id"));
        assertThat(updated.at("/exercises/0/sets/0/weightKg").asInt()).isEqualTo(72);
        assertThat(updated.at("/exercises/2/id").asText()).isEqualTo(ex(body, 2).get("id").asText());
        assertThat(snapshot()).isNotEqualTo(before);
        JsonNode committed = snapshot();
        // A replay, even after a later PUT, returns stored data and cannot revert it.
        body.put("title", "An old POST must not revert the workout");
        set(ex(body, 0)).put("weightKg", 1);
        JsonNode replay = send("POST", tokenB, body, 201);
        assertThat(replay.get("version")).isEqualTo(updated.get("version"));
        assertThat(replay.get("title")).isEqualTo(updated.get("title"));
        assertThat(replay.at("/exercises/0/sets/0/weightKg").asInt()).isEqualTo(72);
        assertThat(snapshot()).isEqualTo(committed);
    }

    @Test
    void postRetryAfterConnectionClosedWithoutReadingResponseIsIdempotent() throws Exception {
        ObjectNode body = payload("Lost response");
        byte[] content = mapper.writeValueAsBytes(body);
        String headers = "POST /api/workouts HTTP/1.1\r\nHost: localhost:" + port
                + "\r\nAuthorization: Bearer " + tokenB
                + "\r\nContent-Type: application/json\r\nContent-Length: " + content.length
                + "\r\nConnection: close\r\n\r\n";
        // Send a real request and lose the connection without reading any response bytes.
        try (Socket socket = new Socket("127.0.0.1", port)) {
            socket.getOutputStream().write(headers.getBytes(StandardCharsets.US_ASCII));
            socket.getOutputStream().write(content);
            socket.getOutputStream().flush();
            socket.shutdownOutput();
        }
        UUID id = UUID.fromString(body.get("id").asText());
        await().atMost(Duration.ofSeconds(10)).until(() -> workouts.existsById(id));
        JsonNode committed = snapshot();
        JsonNode replay = send("POST", tokenB, body, 201);
        assertThat(replay.get("id").asText()).isEqualTo(id.toString());
        assertThat(replay.at("/exercises/0/id").asText()).isEqualTo(ex(body, 0).get("id").asText());
        assertThat(snapshot()).isEqualTo(committed);
        assertThat(workouts.count()).isEqualTo(4);
        assertThat(exercises.count()).isEqualTo(8);
        assertThat(sets.count()).isEqualTo(8);
    }

    @ParameterizedTest(name = "{0}: concurrent new {1} UUID is insert-only")
    @CsvSource({"POST, exercise", "POST, set", "PUT, exercise", "PUT, set"})
    void concurrentUuidCollisionNeverMergesTheWinner(String method, String kind) throws Exception {
        ObjectNode bodyA = "POST".equals(method) ? payload("Winner A") : workoutA.deepCopy();
        ObjectNode bodyB = "POST".equals(method) ? payload("Loser B") : workoutB.deepCopy();
        bodyA.put("title", "Winner change");
        bodyB.put("title", "Must roll back");
        ObjectNode newA = exercise("Winner exercise", 3);
        ObjectNode newB = exercise("Must not overwrite", 3);
        UUID shared = UUID.randomUUID();
        if ("exercise".equals(kind)) {
            newA.put("id", shared.toString());
            newB.put("id", shared.toString());
        } else {
            set(newA).put("id", shared.toString()).put("reps", 12);
            set(newB).put("id", shared.toString()).put("reps", 99);
        }
        bodyA.withArray("exercises").add(newA);
        bodyB.withArray("exercises").add(newB);
        CyclicBarrier bothCheckedAbsent = new CyclicBarrier(2);
        CountDownLatch winnerCommitted = new CountDownLatch(1);
        // Only coordinate the real repository reads. Service writes, flushes, constraints
        // and transactions are real. B resumes with a stale "absent" check AFTER A commits.
        var repository = "exercise".equals(kind) ? exercises : sets;
        doAnswer(invocation -> {
            boolean exists = repository.findById(shared).isPresent();
            assertThat(exists).isFalse();
            bothCheckedAbsent.await(10, TimeUnit.SECONDS);
            if (Thread.currentThread().getName().equals("uuid-loser")) {
                assertThat(winnerCommitted.await(10, TimeUnit.SECONDS)).isTrue();
            }
            return false;
        }).when(repository).existsById(eq(shared));

        JsonNode before = snapshot();
        var pool = Executors.newFixedThreadPool(2);
        try {
            var loser = pool.submit(() -> {
                Thread.currentThread().setName("uuid-loser");
                return request(method, tokenB, bodyB);
            });
            var winner = pool.submit(() -> request(method, tokenA, bodyA));
            MvcResult won = winner.get(15, TimeUnit.SECONDS);
            assertThat(won.getResponse().getStatus()).as(won.getResponse().getContentAsString())
                    .isEqualTo("POST".equals(method) ? 201 : 200);
            JsonNode afterWinner = snapshot();
            winnerCommitted.countDown();
            MvcResult lost = loser.get(15, TimeUnit.SECONDS);
            assertThat(lost.getResponse().getStatus()).as(lost.getResponse().getContentAsString()).isEqualTo(409);
            assertThat(mapper.readTree(lost.getResponse().getContentAsByteArray()))
                    .isEqualTo(mapper.valueToTree(Map.of("error", "Workout conflict: ID already in use")));
            assertThat(snapshot()).isEqualTo(afterWinner);
            assertThat(afterWinner).isNotEqualTo(before);
            for (JsonNode prior : before.get("workout")) {
                if ("POST".equals(method) || !prior.get("TITLE").asText().equals("Account A")) {
                    assertThat(afterWinner.get("workout")).contains(prior);
                }
            }
            for (String table : List.of("workout_exercise", "set_entry")) {
                for (JsonNode prior : before.get(table)) {
                    assertThat(afterWinner.get(table)).contains(prior);
                }
            }
        } finally {
            winnerCommitted.countDown();
            pool.shutdownNow();
            assertThat(pool.awaitTermination(15, TimeUnit.SECONDS)).isTrue();
        }
    }
}
