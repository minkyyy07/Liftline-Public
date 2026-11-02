package com.liftline.app;

import com.liftline.app.security.JwtProperties;
import com.liftline.app.security.JwtService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.context.ConfigurationPropertiesAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtSecretValidationTest {

    @Test
    @DisplayName("JwtProperties throws IllegalStateException when secret is missing or null")
    void shouldFailWhenSecretIsNull() {
        JwtProperties properties = new JwtProperties();
        properties.setSecret(null);

        assertThatThrownBy(properties::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT secret is not configured");
    }

    @Test
    @DisplayName("JwtProperties throws IllegalStateException when secret is blank")
    void shouldFailWhenSecretIsBlank() {
        JwtProperties properties = new JwtProperties();
        properties.setSecret("   ");

        assertThatThrownBy(properties::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT secret is not configured");
    }

    @Test
    @DisplayName("JwtProperties throws IllegalStateException when secret is shorter than 32 bytes")
    void shouldFailWhenSecretIsLessThan32Bytes() {
        JwtProperties properties = new JwtProperties();
        // 31 characters / bytes
        properties.setSecret("1234567890123456789012345678901");

        assertThatThrownBy(properties::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT secret is too short")
                .hasMessageContaining("31 bytes");
    }

    @Test
    @DisplayName("JwtProperties succeeds when secret has exactly 32 bytes")
    void shouldSucceedWhenSecretIs32Bytes() {
        JwtProperties properties = new JwtProperties();
        // Exactly 32 bytes
        properties.setSecret("12345678901234567890123456789012");

        assertThatCode(properties::validate).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("JwtService constructor validates secret from JwtProperties")
    void jwtServiceConstructorValidatesSecret() {
        JwtProperties invalidProperties = new JwtProperties();
        invalidProperties.setSecret("too-short");

        assertThatThrownBy(() -> new JwtService(invalidProperties))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT secret is too short");
    }

    @Test
    @DisplayName("Spring application context fails to start when jwt.secret is missing or empty")
    void contextFailsWhenSecretIsMissing() {
        new ApplicationContextRunner()
                .withConfiguration(AutoConfigurations.of(ConfigurationPropertiesAutoConfiguration.class))
                .withUserConfiguration(JwtProperties.class)
                .withPropertyValues("jwt.secret=")
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure())
                            .hasRootCauseInstanceOf(IllegalStateException.class)
                            .hasRootCauseMessage("JWT secret is not configured. Please set JWT_SECRET environment variable (minimum 32 bytes).");
                });
    }

    @Test
    @DisplayName("Spring application context fails to start when jwt.secret is shorter than 32 bytes")
    void contextFailsWhenSecretIsTooShort() {
        new ApplicationContextRunner()
                .withConfiguration(AutoConfigurations.of(ConfigurationPropertiesAutoConfiguration.class))
                .withUserConfiguration(JwtProperties.class)
                .withPropertyValues("jwt.secret=too-short-secret")
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure())
                            .hasRootCauseInstanceOf(IllegalStateException.class)
                            .hasRootCauseMessage("JWT secret is too short: length is 16 bytes, but at least 32 bytes (256 bits) required. Please update JWT_SECRET.");
                });
    }

    @Test
    @DisplayName("Spring application context succeeds when jwt.secret has at least 32 bytes")
    void contextSucceedsWhenSecretIsValid() {
        new ApplicationContextRunner()
                .withConfiguration(AutoConfigurations.of(ConfigurationPropertiesAutoConfiguration.class))
                .withUserConfiguration(JwtProperties.class)
                .withPropertyValues("jwt.secret=this-is-a-valid-secret-key-that-is-at-least-32-bytes-long")
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context).hasSingleBean(JwtProperties.class);
                });
    }
}
