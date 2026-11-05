package com.liftline.app;

import com.liftline.app.config.GlobalExceptionHandler;
import jakarta.persistence.LockTimeoutException;
import jakarta.persistence.PersistenceException;
import jakarta.persistence.PessimisticLockException;
import jakarta.persistence.RollbackException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.jpa.JpaSystemException;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.sql.SQLException;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class TransactionLockErrorTests {
    private final FailingController controller = new FailingController();
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler()).build();
    }

    static Stream<RuntimeException> lockFailures() {
        return Stream.of(
                new CannotAcquireLockException("deadlock"),
                new PessimisticLockException("deadlock"),
                new LockTimeoutException("timeout"),
                new JpaSystemException(new RollbackException("commit",
                        new PersistenceException(new SQLException("deadlock", "40001", 1213)))),
                new TransactionSystemException("commit",
                        new RollbackException("rollback", new SQLException("timeout", "HY000", 1205))));
    }

    @ParameterizedTest
    @MethodSource("lockFailures")
    void lockFailuresIncludingCommitWrappersAreRetryable(RuntimeException failure) throws Exception {
        controller.failure = failure;
        mvc.perform(post("/failure"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().string("Retry-After", "1"))
                .andExpect(jsonPath("$.error").value("Temporary database lock conflict; retry the entire request"))
                .andExpect(jsonPath("$.code").value("DATABASE_LOCK_RETRY"))
                .andExpect(jsonPath("$.retryable").value(true));
    }

    @Test
    void unrelatedCommitFailureIsNotAdvertisedAsRetryable() {
        controller.failure = new TransactionSystemException("commit",
                new RollbackException("rollback", new SQLException("connection lost", "08006", 0)));
        assertThatThrownBy(() -> mvc.perform(post("/failure")))
                .hasCause(controller.failure);
    }

    @Test
    void integrityFailureIsNotAdvertisedAsRetryable() throws Exception {
        controller.failure = new DataIntegrityViolationException("duplicate");
        mvc.perform(post("/failure")).andExpect(status().isBadRequest())
                .andExpect(header().doesNotExist("Retry-After"))
                .andExpect(jsonPath("$.retryable").doesNotExist());
    }

    @RestController
    static class FailingController {
        private RuntimeException failure;

        @PostMapping("/failure")
        void fail() {
            throw failure;
        }
    }
}
