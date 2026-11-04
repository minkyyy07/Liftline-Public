package com.liftline.app.controller;

import com.liftline.app.dto.ChangePasswordRequest;
import com.liftline.app.dto.UpdateProfileRequest;
import com.liftline.app.dto.UserProfileDto;
import com.liftline.app.entity.User;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.service.RefreshTokenService;
import com.liftline.app.service.WorkoutService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/user")
public class UserController {

    private final UserRepository userRepository;
    private final WorkoutService workoutService;
    private final PasswordEncoder passwordEncoder;
    private final RefreshTokenService refreshTokenService;

    public UserController(UserRepository userRepository,
                          WorkoutService workoutService,
                          PasswordEncoder passwordEncoder,
                          RefreshTokenService refreshTokenService) {
        this.userRepository = userRepository;
        this.workoutService = workoutService;
        this.passwordEncoder = passwordEncoder;
        this.refreshTokenService = refreshTokenService;
    }

    @GetMapping("/profile")
    public ResponseEntity<UserProfileDto> getProfile() {
        User user = workoutService.getAuthenticatedUser();
        return ResponseEntity.ok(new UserProfileDto(user.getId(), user.getEmail(), user.getDisplayName()));
    }

    @PatchMapping("/profile")
    public ResponseEntity<UserProfileDto> updateProfile(@Valid @RequestBody UpdateProfileRequest request) {
        User user = workoutService.getAuthenticatedUser();
        if (request.getDisplayName() != null) {
            user.setDisplayName(request.getDisplayName().trim());
        }
        User saved = userRepository.save(user);
        return ResponseEntity.ok(new UserProfileDto(saved.getId(), saved.getEmail(), saved.getDisplayName()));
    }

    @PostMapping("/change-password")
    public ResponseEntity<?> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        User user = workoutService.getAuthenticatedUser();

        if (!passwordEncoder.matches(request.getCurrentPassword(), user.getPasswordHash())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Current password does not match"));
        }

        user.setPasswordHash(passwordEncoder.encode(request.getNewPassword()));
        userRepository.save(user);

        // Revoke all refresh sessions on password change
        refreshTokenService.revokeAllForUser(user.getId());

        return ResponseEntity.ok(Map.of("message", "Password changed successfully. All sessions revoked."));
    }
}
