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
import org.hibernate.resource.jdbc.spi.StatementInspector;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.orm.jpa.HibernatePropertiesCustomizer;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.SpyBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.ByteBuffer;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.reset;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(WorkoutMySqlIT.SqlConfiguration.class)
class WorkoutMySqlIT {
    @DynamicPropertySource
    static void mysql(DynamicPropertyRegistry properties) {
        String url = System.getenv("MYSQL_TEST_URL");
        if (url == null || !url.startsWith("jdbc:mysql://")) {
            throw new IllegalStateException("MYSQL_TEST_URL must point to a dedicated MySQL test database (not H2)");
        }
        properties.add("spring.datasource.url", () -> url);
        properties.add("spring.datasource.username", () -> System.getenv("MYSQL_TEST_USERNAME"));
        properties.add("spring.datasource.password", () -> System.getenv().getOrDefault("MYSQL_TEST_PASSWORD", ""));
        properties.add("spring.datasource.driver-class-name", () -> "com.mysql.cj.jdbc.Driver");
        properties.add("spring.datasource.hikari.connection-init-sql", () -> "SET SESSION innodb_lock_wait_timeout=2");
        properties.add("spring.jpa.properties.hibernate.jdbc.batch_size", () -> "0");
        properties.add("spring.jpa.properties.hibernate.order_inserts", () -> "false");
    }

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper mapper;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private UserRepository users;
    @Autowired private RefreshSessionRepository sessions;
    @Autowired private PasswordEncoder passwords;
    @Autowired private AuthRateLimiter rateLimiter;
    @Autowired private PlatformTransactionManager transactions;
    @Autowired private WriteOverlap overlap;
    @SpyBean private WorkoutRepository workouts;
    @SpyBean private WorkoutExerciseRepository exercises;
    @SpyBean private SetEntryRepository sets;

    private String tokenA;
    private String tokenB;
    private ObjectNode workoutA;
    private ObjectNode workoutB;

    @BeforeEach
    void setUp() throws Exception {
        assertThat(jdbc.queryForObject("SELECT VERSION()", String.class)).doesNotContainIgnoringCase("mariadb");
        assertThat(jdbc.queryForList("SELECT ENGINE FROM information_schema.tables "
                + "WHERE table_schema=DATABASE() AND table_name IN ('workout','workout_exercise','set_entry')",
                String.class)).hasSize(3).containsOnly("InnoDB");
        assertThat(jdbc.queryForObject("SELECT @@innodb_rollback_on_timeout", Boolean.class)).isFalse();
        rateLimiter.reset();
        tokenA = login("mysql-a@example.com");
        tokenB = login("mysql-b@example.com");
        workoutA = payload("Account A");
        workoutB = payload("Account B");
        workoutA.withArray("exercises").add(exercise("Original A", 1));
        workoutB.withArray("exercises").add(exercise("Original B", 1));
        send("POST", tokenA, workoutA, 201);
        send("POST", tokenB, workoutB, 201);
    }

    @AfterEach
    void tearDown() {
        overlap.table = null;
        reset(workouts, exercises, sets);
        workouts.deleteAll();
        sessions.deleteAll();
        users.deleteAll();
    }

    @ParameterizedTest(name = "{0}, {1}, commit flush={2}: opposite X/Y insert order")
    @CsvSource({"POST, exercise, false", "POST, set, false", "PUT, exercise, false", "PUT, set, false",
            "POST, exercise, true", "POST, set, true", "PUT, exercise, true", "PUT, set, true"})
    void oppositeInsertOrderDeadlocksWithoutTakingOverRows(String method, String kind, boolean commitFlush)
            throws Exception {
        ObjectNode bodyA = change(method, workoutA, "Change A");
        ObjectNode bodyB = change(method, workoutB, "Change B");
        UUID x = UUID.randomUUID();
        UUID y = UUID.randomUUID();
        addShared(bodyA, kind, x, y);
        addShared(bodyB, kind, y, x);
        CyclicBarrier bothValidated = new CyclicBarrier(2);
        Map<String, Integer> reads = new ConcurrentHashMap<>();
        var repository = "exercise".equals(kind) ? exercises : sets;
        doAnswer(invocation -> {
            UUID id = invocation.getArgument(0);
            boolean present = repository.findById(id).isPresent();
            if (id.equals(x) || id.equals(y)) {
                assertThat(present).isFalse();
                if (reads.merge(Thread.currentThread().getName(), 1, Integer::sum) == 2) {
                    bothValidated.await(15, TimeUnit.SECONDS);
                }
            }
            return present;
        }).when(repository).existsById(any(UUID.class));
        overlap.start(kind);
        if (commitFlush) {
            // Only defer the explicit flush: actual SQL/locking now runs in JpaTransactionManager.doCommit.
            doNothing().when(workouts).flush();
        }
        JsonNode before = snapshot();
        var pool = Executors.newFixedThreadPool(2);
        try {
            var a = pool.submit(() -> {
                Thread.currentThread().setName("mysql-race-a");
                return request(method, tokenA, bodyA);
            });
            var b = pool.submit(() -> {
                Thread.currentThread().setName("mysql-race-b");
                return request(method, tokenB, bodyB);
            });
            MvcResult resultA = a.get(30, TimeUnit.SECONDS);
            MvcResult resultB = b.get(30, TimeUnit.SECONDS);
            assertThat(overlap.secondInserts.get()).isEqualTo(2);
            assertThat(overlap.atCommit.values()).hasSize(2).containsOnly(commitFlush);
            boolean aWon = resultA.getResponse().getStatus() != 503;
            MvcResult winner = aWon ? resultA : resultB;
            MvcResult loser = aWon ? resultB : resultA;
            assertThat(winner.getResponse().getStatus()).isEqualTo("POST".equals(method) ? 201 : 200);
            assertRetryable(loser, 1213);
            overlap.table = null;
            reset(workouts, exercises, sets);
            JsonNode committed = snapshot();
            assertOnlyWinnerChanged(before, committed, aWon ? workoutA : workoutB, method, 2);
            assertWritten(committed, aWon ? bodyA : bodyB);
            // The identical retry is now a permanent ownership conflict, not a transient lock.
            MvcResult ownershipConflict = request(method, aWon ? tokenB : tokenA, aWon ? bodyB : bodyA);
            assertThat(ownershipConflict.getResponse().getStatus()).isEqualTo(409);
            assertThat(ownershipConflict.getResponse().getHeader("Retry-After")).isNull();
            assertThat(mapper.readTree(ownershipConflict.getResponse().getContentAsByteArray()))
                    .isEqualTo(mapper.valueToTree(Map.of("error", "Workout conflict: ID already in use")));
            assertThat(snapshot()).isEqualTo(committed);
            assertReplay(method, aWon ? tokenA : tokenB, aWon ? bodyA : bodyB, committed);
            assertRevision(committed, aWon ? workoutA : workoutB, "POST".equals(method) ? 0 : 1);
            if ("POST".equals(method)) {
                assertRevision(committed, aWon ? bodyA : bodyB, 0);
            }
        } finally {
            pool.shutdownNow();
            assertThat(pool.awaitTermination(15, TimeUnit.SECONDS)).isTrue();
        }
    }

    @ParameterizedTest(name = "{0}, {1}, commit flush={2}: lock timeout and safe retry")
    @CsvSource({"POST, exercise, false", "POST, set, false", "PUT, exercise, false", "PUT, set, false",
            "POST, exercise, true", "POST, set, true", "PUT, exercise, true", "PUT, set, true"})
    void timeoutRollsBackEntireRequestAndCanBeRetried(String method, String kind, boolean commitFlush)
            throws Exception {
        UUID shared = UUID.randomUUID();
        ObjectNode body = change(method, workoutB, "Retry B");
        // A private child is inserted before hitting the lock; it must also be rolled back.
        body.withArray("exercises").add(exercise("Private insert before timeout", 2));
        addShared(body, kind, shared, UUID.randomUUID());
        JsonNode before = snapshot();
        CountDownLatch locked = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        var pool = Executors.newSingleThreadExecutor();
        try {
            var holder = pool.submit(() -> newTransaction().execute(status -> {
                if ("exercise".equals(kind)) {
                    jdbc.update("INSERT INTO workout_exercise "
                            + "(id,workout_id,exercise_name,sort_order,created_at,updated_at) VALUES (?,?,?,1,NOW(),NOW())",
                            binary(shared), binary(UUID.fromString(workoutA.get("id").asText())), "Uncommitted A");
                } else {
                    jdbc.update("INSERT INTO set_entry "
                            + "(id,exercise_id,set_number,completed,created_at,updated_at) VALUES (?,?,1,true,NOW(),NOW())",
                            binary(shared), binary(UUID.fromString(ex(workoutA, 0).get("id").asText())));
                }
                locked.countDown();
                try {
                    assertThat(release.await(20, TimeUnit.SECONDS)).isTrue();
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException(interrupted);
                } finally {
                    status.setRollbackOnly();
                }
                return null;
            }));
            assertThat(locked.await(10, TimeUnit.SECONDS)).isTrue();
            if (commitFlush) {
                doNothing().when(workouts).flush();
            }
            assertRetryable(request(method, tokenB, body), 1205);
            release.countDown();
            holder.get(10, TimeUnit.SECONDS);
            reset(workouts);
            assertThat(snapshot()).isEqualTo(before);
            send(method, tokenB, body, "POST".equals(method) ? 201 : 200);
            JsonNode committed = snapshot();
            assertOnlyWinnerChanged(before, committed, workoutB, method, 3);
            assertWritten(committed, body);
            assertRevision(committed, body, "POST".equals(method) ? 0 : 1);
            assertReplay(method, tokenB, body, committed);
        } finally {
            release.countDown();
            pool.shutdownNow();
            assertThat(pool.awaitTermination(15, TimeUnit.SECONDS)).isTrue();
        }
    }

    private TransactionTemplate newTransaction() {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return tx;
    }

    private JsonNode snapshot() {
        return newTransaction().execute(status -> {
            Map<String, Object> tables = new LinkedHashMap<>();
            for (String table : List.of("workout", "workout_exercise", "set_entry")) {
                tables.put(table, jdbc.queryForList("SELECT * FROM " + table + " ORDER BY id"));
            }
            return mapper.valueToTree(tables);
        });
    }

    private void assertOnlyWinnerChanged(JsonNode before, JsonNode after, ObjectNode winner, String method, int added) {
        String winnerId = mapper.valueToTree(binary(UUID.fromString(winner.get("id").asText()))).asText();
        for (String table : List.of("workout", "workout_exercise", "set_entry")) {
            for (JsonNode prior : before.get(table)) {
                if ("PUT".equals(method) && table.equals("workout") && prior.get("id").asText().equals(winnerId)) {
                    continue;
                }
                if ("PUT".equals(method) && table.equals("set_entry")
                        && prior.get("id").asText().equals(mapper.valueToTree(binary(UUID.fromString(
                                set(ex(winner, 0)).get("id").asText()))).asText())) {
                    continue;
                }
                assertThat(after.get(table)).contains(prior);
            }
        }
        assertThat(after.get("workout").size()).isEqualTo(before.get("workout").size() + ("POST".equals(method) ? 1 : 0));
        assertThat(after.get("workout_exercise").size()).isEqualTo(before.get("workout_exercise").size()
                + added);
        assertThat(after.get("set_entry").size()).isEqualTo(before.get("set_entry").size()
                + added);
    }

    private void assertWritten(JsonNode snapshot, ObjectNode body) {
        JsonNode workoutId = mapper.valueToTree(binary(UUID.fromString(body.get("id").asText())));
        for (JsonNode exercise : body.withArray("exercises")) {
            JsonNode exerciseId = mapper.valueToTree(binary(UUID.fromString(exercise.get("id").asText())));
            assertThat(snapshot.get("workout_exercise")).anySatisfy(row -> {
                assertThat(row.get("id")).isEqualTo(exerciseId);
                assertThat(row.get("workout_id")).isEqualTo(workoutId);
                assertThat(row.get("exercise_name").asText()).isEqualTo(exercise.get("exerciseName").asText());
            });
            for (JsonNode set : exercise.get("sets")) {
                JsonNode setId = mapper.valueToTree(binary(UUID.fromString(set.get("id").asText())));
                assertThat(snapshot.get("set_entry")).anySatisfy(row -> {
                    assertThat(row.get("id")).isEqualTo(setId);
                    assertThat(row.get("exercise_id")).isEqualTo(exerciseId);
                    assertThat(row.get("reps").asInt()).isEqualTo(set.get("reps").asInt());
                });
            }
        }
    }

    private void assertRevision(JsonNode snapshot, ObjectNode body, long revision) {
        JsonNode id = mapper.valueToTree(binary(UUID.fromString(body.get("id").asText())));
        assertThat(snapshot.get("workout")).anySatisfy(row -> {
            assertThat(row.get("id")).isEqualTo(id);
            assertThat(row.get("version").asLong()).isEqualTo(revision);
        });
    }

    private void assertReplay(String method, String token, ObjectNode body, JsonNode committed) throws Exception {
        send(method, token, body, "POST".equals(method) ? 201 : 409);
        assertThat(snapshot()).isEqualTo(committed);
    }

    private void assertRetryable(MvcResult result, int vendorCode) throws Exception {
        assertThat(result.getResponse().getStatus()).as(result.getResponse().getContentAsString()).isEqualTo(503);
        assertThat(result.getResponse().getHeader("Retry-After")).isEqualTo("1");
        assertThat(mapper.readTree(result.getResponse().getContentAsByteArray())).isEqualTo(mapper.valueToTree(Map.of(
                "error", "Temporary database lock conflict; retry the entire request",
                "code", "DATABASE_LOCK_RETRY", "retryable", true)));
        Throwable failure = result.getResolvedException();
        assertThat(failure).isExactlyInstanceOf(vendorCode == 1213
                ? CannotAcquireLockException.class : PessimisticLockingFailureException.class);
        StringBuilder chain = new StringBuilder();
        SQLException sql = null;
        for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
            chain.append(cause.getClass().getName()).append(" -> ");
            if (cause instanceof SQLException exception) {
                sql = exception;
            }
        }
        assertThat((Throwable) sql).as(chain.toString()).isNotNull();
        assertThat(sql.getErrorCode()).as(chain.toString()).isEqualTo(vendorCode);
        System.out.println("MySQL " + vendorCode + " SQLState=" + sql.getSQLState() + ": " + chain);
    }

    private String login(String email) throws Exception {
        users.save(new User(email, passwords.encode("password123")));
        MvcResult result = mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content(mapper.writeValueAsBytes(Map.of("email", email, "password", "password123")))).andReturn();
        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        return mapper.readTree(result.getResponse().getContentAsByteArray()).get("accessToken").asText();
    }

    private ObjectNode payload(String title) {
        ObjectNode body = mapper.createObjectNode().put("id", UUID.randomUUID().toString()).put("title", title)
                .put("workoutDate", "2026-11-05").put("notes", "original notes").put("version", 0);
        body.putArray("exercises");
        return body;
    }

    private ObjectNode change(String method, ObjectNode original, String title) {
        ObjectNode body = "POST".equals(method) ? payload(title) : original.deepCopy();
        body.put("title", title).put("notes", "changed notes");
        if ("PUT".equals(method)) {
            set(ex(body, 0)).put("reps", 99);
        }
        return body;
    }

    private ObjectNode exercise(String name, int order) {
        ObjectNode exercise = mapper.createObjectNode().put("id", UUID.randomUUID().toString())
                .put("exerciseName", name).put("sortOrder", order);
        exercise.putArray("sets").add(mapper.createObjectNode().put("id", UUID.randomUUID().toString())
                .put("setNumber", 1).put("weightKg", 60).put("reps", 8).put("completed", true));
        return exercise;
    }

    private void addShared(ObjectNode body, String kind, UUID first, UUID second) {
        for (UUID id : List.of(first, second)) {
            ObjectNode exercise = exercise("New " + id, body.withArray("exercises").size() + 1);
            ("exercise".equals(kind) ? exercise : set(exercise)).put("id", id.toString());
            body.withArray("exercises").add(exercise);
        }
    }

    private static ObjectNode ex(ObjectNode body, int index) {
        return (ObjectNode) body.withArray("exercises").get(index);
    }

    private static ObjectNode set(ObjectNode exercise) {
        return (ObjectNode) exercise.withArray("sets").get(0);
    }

    private static byte[] binary(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }

    private MvcResult request(String method, String token, ObjectNode body) throws Exception {
        var builder = "PUT".equals(method) ? put("/api/workouts/" + body.get("id").asText()) : post("/api/workouts");
        return mvc.perform(builder.header("Authorization", "Bearer " + token).contentType(MediaType.APPLICATION_JSON)
                .content(mapper.writeValueAsBytes(body))).andReturn();
    }

    private void send(String method, String token, ObjectNode body, int expected) throws Exception {
        MvcResult result = request(method, token, body);
        assertThat(result.getResponse().getStatus()).as(result.getResponse().getContentAsString()).isEqualTo(expected);
    }

    static class WriteOverlap implements StatementInspector {
        volatile String table;
        final AtomicInteger secondInserts = new AtomicInteger();
        final Map<String, Boolean> atCommit = new ConcurrentHashMap<>();
        private final Map<String, Integer> inserts = new ConcurrentHashMap<>();
        private CyclicBarrier bothInserted;

        void start(String kind) {
            inserts.clear();
            atCommit.clear();
            secondInserts.set(0);
            bothInserted = new CyclicBarrier(2);
            table = "exercise".equals(kind) ? "workout_exercise" : "set_entry";
        }

        @Override
        public String inspect(String sql) {
            String name = Thread.currentThread().getName();
            if (table != null && name.startsWith("mysql-race-")
                    && sql.toLowerCase(Locale.ROOT).startsWith("insert into " + table + " ")
                    && inserts.merge(name, 1, Integer::sum) == 2) {
                // Batching is disabled: each connection has already executed its first INSERT.
                // Neither transaction may attempt the opposing INSERT until both hold their row lock.
                atCommit.put(name, StackWalker.getInstance().walk(frames -> frames.anyMatch(frame ->
                        frame.getClassName().equals("org.springframework.orm.jpa.JpaTransactionManager")
                                && frame.getMethodName().equals("doCommit"))));
                secondInserts.incrementAndGet();
                try {
                    bothInserted.await(15, TimeUnit.SECONDS);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException(interrupted);
                } catch (Exception failure) {
                    throw new IllegalStateException("Transactions did not overlap at INSERT", failure);
                }
            }
            return sql;
        }
    }

    @TestConfiguration
    static class SqlConfiguration {
        @Bean
        WriteOverlap writeOverlap() {
            return new WriteOverlap();
        }

        @Bean
        HibernatePropertiesCustomizer inspectWrites(WriteOverlap inspector) {
            return properties -> properties.put("hibernate.session_factory.statement_inspector", inspector);
        }
    }
}
