package com.liftline.app.dto;

import jakarta.validation.Constraint;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.nio.charset.StandardCharsets;

@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = BcryptPassword.Validator.class)
@Documented
public @interface BcryptPassword {
    String message() default "Password must be between 8 characters and 72 bytes in UTF-8";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};

    class Validator implements ConstraintValidator<BcryptPassword, String> {
        public static final int MIN_CHARS = 8;
        public static final int MAX_BYTES = 72;

        @Override
        public boolean isValid(String password, ConstraintValidatorContext context) {
            if (password == null) {
                return true;
            }
            if (password.length() < MIN_CHARS) {
                context.disableDefaultConstraintViolation();
                context.buildConstraintViolationWithTemplate("Password must be at least " + MIN_CHARS + " characters")
                        .addConstraintViolation();
                return false;
            }
            byte[] utf8Bytes = password.getBytes(StandardCharsets.UTF_8);
            if (utf8Bytes.length > MAX_BYTES) {
                context.disableDefaultConstraintViolation();
                context.buildConstraintViolationWithTemplate("Password length in UTF-8 must not exceed " + MAX_BYTES + " bytes (BCrypt limit)")
                        .addConstraintViolation();
                return false;
            }
            return true;
        }
    }
}
