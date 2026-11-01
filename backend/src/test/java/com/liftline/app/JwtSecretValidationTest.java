package com.liftline.app;

import com.liftline.app.security.JwtProperties;
import com.liftline.app.security.JwtService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

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
}
