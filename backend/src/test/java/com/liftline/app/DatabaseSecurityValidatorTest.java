package com.liftline.app;

import com.liftline.app.config.DatabaseSecurityValidator;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class DatabaseSecurityValidatorTest {

    @Test
    @DisplayName("Validator is bypassed when dev or test profile is active")
    void devAndTestProfilesAreBypassed() {
        MockEnvironment devEnv = new MockEnvironment();
        devEnv.setActiveProfiles("dev");

        assertThatCode(() -> DatabaseSecurityValidator.validateEnvironment(devEnv))
                .doesNotThrowAnyException();

        MockEnvironment testEnv = new MockEnvironment();
        testEnv.setActiveProfiles("test");

        assertThatCode(() -> DatabaseSecurityValidator.validateEnvironment(testEnv))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("Validator is bypassed when datasource url is H2")
    void h2UrlIsBypassed() {
        MockEnvironment env = new MockEnvironment();
        env.setProperty("spring.datasource.url", "jdbc:h2:mem:liftline");

        assertThatCode(() -> DatabaseSecurityValidator.validateEnvironment(env))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("Production fails when DB_URL is missing")
    void productionFailsWhenDbUrlIsMissing() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");
        prodEnv.setProperty("spring.datasource.url", "");
        prodEnv.setProperty("spring.datasource.username", "app_user");
        prodEnv.setProperty("spring.datasource.password", "secure_pass");

        assertThatThrownBy(() -> DatabaseSecurityValidator.validateEnvironment(prodEnv))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("DB_URL");
    }

    @Test
    @DisplayName("Production fails when DB_USERNAME is missing")
    void productionFailsWhenDbUsernameIsMissing() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");
        prodEnv.setProperty("spring.datasource.url", "jdbc:mysql://localhost:3306/liftline");
        prodEnv.setProperty("spring.datasource.username", "");
        prodEnv.setProperty("spring.datasource.password", "secure_pass");

        assertThatThrownBy(() -> DatabaseSecurityValidator.validateEnvironment(prodEnv))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("DB_USERNAME");
    }

    @Test
    @DisplayName("Production fails when DB_USERNAME is 'root'")
    void productionFailsWhenRootUserIsConfigured() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");
        prodEnv.setProperty("spring.datasource.url", "jdbc:mysql://localhost:3306/liftline");
        prodEnv.setProperty("spring.datasource.username", "root");
        prodEnv.setProperty("spring.datasource.password", "secure_pass");

        assertThatThrownBy(() -> DatabaseSecurityValidator.validateEnvironment(prodEnv))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("root");
    }

    @Test
    @DisplayName("Production fails when DB_PASSWORD is missing or blank")
    void productionFailsWhenPasswordIsMissing() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");
        prodEnv.setProperty("spring.datasource.url", "jdbc:mysql://localhost:3306/liftline");
        prodEnv.setProperty("spring.datasource.username", "liftline_app");
        prodEnv.setProperty("spring.datasource.password", "   ");

        assertThatThrownBy(() -> DatabaseSecurityValidator.validateEnvironment(prodEnv))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("DB_PASSWORD");
    }

    @Test
    @DisplayName("Production fails when remote MySQL disables TLS")
    void productionFailsWhenRemoteMysqlDisablesTls() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");
        prodEnv.setProperty("spring.datasource.url", "jdbc:mysql://db.production.internal:3306/liftline?useSSL=false");
        prodEnv.setProperty("spring.datasource.username", "liftline_user");
        prodEnv.setProperty("spring.datasource.password", "strong_password");

        assertThatThrownBy(() -> DatabaseSecurityValidator.validateEnvironment(prodEnv))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("verified TLS");
    }

    @Test
    @DisplayName("Production succeeds with valid remote MySQL and verified TLS")
    void productionSucceedsWithValidRemoteTlsConfiguration() {
        MockEnvironment prodEnv = new MockEnvironment();
        prodEnv.setActiveProfiles("production");
        prodEnv.setProperty("spring.datasource.url", "jdbc:mysql://db.production.internal:3306/liftline?sslMode=VERIFY_IDENTITY");
        prodEnv.setProperty("spring.datasource.username", "liftline_user");
        prodEnv.setProperty("spring.datasource.password", "strong_production_password");

        assertThatCode(() -> DatabaseSecurityValidator.validateEnvironment(prodEnv))
                .doesNotThrowAnyException();
    }
}
