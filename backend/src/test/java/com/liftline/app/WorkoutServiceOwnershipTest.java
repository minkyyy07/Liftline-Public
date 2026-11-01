package com.liftline.app;

import com.liftline.app.entity.User;
import com.liftline.app.entity.Workout;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.repository.WorkoutRepository;
import com.liftline.app.service.WorkoutService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@ActiveProfiles("test")
class WorkoutServiceOwnershipTest {

    @Autowired
    private WorkoutService workoutService;

    @Autowired
    private WorkoutRepository workoutRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    private User userA;
    private User userB;

    @BeforeEach
    void setUp() {
        workoutRepository.deleteAll();
        userRepository.deleteAll();

        userA = userRepository.save(new User("usera@example.com", passwordEncoder.encode("password123")));
        userB = userRepository.save(new User("userb@example.com", passwordEncoder.encode("password123")));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
        workoutRepository.deleteAll();
        userRepository.deleteAll();
    }

    private void authenticateAs(User user) {
        var auth = new UsernamePasswordAuthenticationToken(
                user.getEmail(),
                null,
                List.of(new SimpleGrantedAuthority("USER"))
        );
        SecurityContextHolder.getContext().setAuthentication(auth);
    }

    @Test
    @DisplayName("User cannot read another user's workout")
    void userCannotReadAnotherUserWorkout() {
        authenticateAs(userA);
        Workout workoutA = new Workout();
        workoutA.setTitle("User A Chest Workout");
        workoutA.setWorkoutDate(LocalDate.now());
        workoutA.setDurationMinutes(60);
        workoutA = workoutService.createWorkoutForCurrentUser(workoutA);

        authenticateAs(userB);
        final Workout finalWorkoutA = workoutA;

        // User B cannot get User A's workout by ID
        assertThatThrownBy(() -> workoutService.getWorkoutByIdForCurrentUser(finalWorkoutA.getId()))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessageContaining("access denied");

        // User B's workout list does not include User A's workout
        List<Workout> userBWorkouts = workoutService.getCurrentUserWorkouts();
        assertThat(userBWorkouts).isEmpty();
    }

    @Test
    @DisplayName("User cannot update another user's workout")
    void userCannotUpdateAnotherUserWorkout() {
        authenticateAs(userA);
        Workout workoutA = new Workout();
        workoutA.setTitle("Original Title");
        workoutA.setWorkoutDate(LocalDate.now());
        workoutA.setDurationMinutes(45);
        workoutA = workoutService.createWorkoutForCurrentUser(workoutA);

        // Switch to User B and attempt to modify User A's workout
        authenticateAs(userB);
        Workout hostileUpdate = new Workout();
        hostileUpdate.setId(workoutA.getId());
        hostileUpdate.setTitle("Hacked Title");
        hostileUpdate.setWorkoutDate(LocalDate.now());
        hostileUpdate.setDurationMinutes(999);

        assertThatThrownBy(() -> workoutService.updateWorkoutForCurrentUser(hostileUpdate))
                .isInstanceOf(AccessDeniedException.class);

        // Verify User A's data remains unmodified in database
        Workout persisted = workoutRepository.findById(workoutA.getId()).orElseThrow();
        assertThat(persisted.getTitle()).isEqualTo("Original Title");
        assertThat(persisted.getDurationMinutes()).isEqualTo(45);
    }

    @Test
    @DisplayName("User cannot delete another user's workout")
    void userCannotDeleteAnotherUserWorkout() {
        authenticateAs(userA);
        Workout workoutA = new Workout();
        workoutA.setTitle("Leg Day");
        workoutA.setWorkoutDate(LocalDate.now());
        workoutA.setDurationMinutes(50);
        workoutA = workoutService.createWorkoutForCurrentUser(workoutA);

        // Switch to User B and attempt to delete User A's workout
        authenticateAs(userB);
        final Workout finalWorkoutA = workoutA;
        assertThatThrownBy(() -> workoutService.deleteWorkoutForCurrentUser(finalWorkoutA.getId()))
                .isInstanceOf(AccessDeniedException.class);

        // Verify workout still exists in repository
        assertThat(workoutRepository.existsById(workoutA.getId())).isTrue();
    }

    @Test
    @DisplayName("Owner can read, update and delete their own workout")
    void ownerCanManageOwnWorkout() {
        authenticateAs(userA);
        Workout workout = new Workout();
        workout.setTitle("Shoulders");
        workout.setWorkoutDate(LocalDate.now());
        workout.setDurationMinutes(30);

        Workout created = workoutService.createWorkoutForCurrentUser(workout);
        assertThat(created.getId()).isNotNull();

        // Read
        Workout retrieved = workoutService.getWorkoutByIdForCurrentUser(created.getId());
        assertThat(retrieved.getTitle()).isEqualTo("Shoulders");

        // Update
        retrieved.setTitle("Heavy Shoulders");
        retrieved.setDurationMinutes(40);
        Workout updated = workoutService.updateWorkoutForCurrentUser(retrieved);
        assertThat(updated.getTitle()).isEqualTo("Heavy Shoulders");
        assertThat(updated.getDurationMinutes()).isEqualTo(40);

        // Delete
        workoutService.deleteWorkoutForCurrentUser(created.getId());
        assertThat(workoutRepository.existsById(created.getId())).isFalse();
    }

    @Test
    @DisplayName("Owner-scoped programmatic methods reject mismatched ownerId")
    void ownerScopedMethodsEnforceOwnerId() {
        Workout workoutA = new Workout();
        workoutA.setTitle("Back Workout");
        workoutA.setWorkoutDate(LocalDate.now());
        Workout created = workoutService.createWorkoutForOwner(workoutA, userA);

        // User B cannot update with userB ID
        created.setTitle("Tampered");
        assertThatThrownBy(() -> workoutService.updateWorkoutForOwner(created, userB.getId()))
                .isInstanceOf(AccessDeniedException.class);

        // User B cannot delete with userB ID
        assertThatThrownBy(() -> workoutService.deleteWorkoutForOwner(created.getId(), userB.getId()))
                .isInstanceOf(AccessDeniedException.class);

        // Still exists
        assertThat(workoutRepository.existsById(created.getId())).isTrue();
    }
}
