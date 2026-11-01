package com.liftline.app.service;

import com.liftline.app.entity.User;
import com.liftline.app.entity.Workout;
import com.liftline.app.repository.SetEntryRepository;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.repository.WorkoutExerciseRepository;
import com.liftline.app.repository.WorkoutRepository;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
@Transactional
public class WorkoutService {
    private final WorkoutRepository workoutRepository;
    private final WorkoutExerciseRepository workoutExerciseRepository;
    private final SetEntryRepository setEntryRepository;
    private final UserRepository userRepository;

    public WorkoutService(WorkoutRepository workoutRepository,
                          WorkoutExerciseRepository workoutExerciseRepository,
                          SetEntryRepository setEntryRepository,
                          UserRepository userRepository) {
        this.workoutRepository = workoutRepository;
        this.workoutExerciseRepository = workoutExerciseRepository;
        this.setEntryRepository = setEntryRepository;
        this.userRepository = userRepository;
    }

    /**
     * Resolves the current authenticated user from SecurityContextHolder.
     * Prevents accepting userId from untrusted client parameters.
     */
    public User getAuthenticatedUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || "anonymousUser".equals(auth.getPrincipal())) {
            throw new AccessDeniedException("User is not authenticated");
        }
        String email = auth.getName();
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new AccessDeniedException("Authenticated user not found"));
    }

    @Transactional(readOnly = true)
    public List<Workout> getCurrentUserWorkouts() {
        User user = getAuthenticatedUser();
        return workoutRepository.findByUserIdOrderByWorkoutDateDesc(user.getId());
    }

    @Transactional(readOnly = true)
    public Workout getWorkoutByIdForCurrentUser(UUID workoutId) {
        User user = getAuthenticatedUser();
        return workoutRepository.findByIdAndUserId(workoutId, user.getId())
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));
    }

    public Workout createWorkoutForCurrentUser(Workout workout) {
        User user = getAuthenticatedUser();
        workout.setUser(user);
        return workoutRepository.save(workout);
    }

    public Workout updateWorkoutForCurrentUser(Workout workout) {
        if (workout.getId() == null) {
            throw new IllegalArgumentException("Workout ID must not be null for update");
        }
        User user = getAuthenticatedUser();
        Workout existing = workoutRepository.findByIdAndUserId(workout.getId(), user.getId())
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));

        existing.setTitle(workout.getTitle());
        existing.setWorkoutDate(workout.getWorkoutDate());
        existing.setDurationMinutes(workout.getDurationMinutes());
        existing.setNotes(workout.getNotes());
        return workoutRepository.save(existing);
    }

    public void deleteWorkoutForCurrentUser(UUID workoutId) {
        User user = getAuthenticatedUser();
        Workout existing = workoutRepository.findByIdAndUserId(workoutId, user.getId())
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));
        workoutRepository.delete(existing);
    }

    // Owner-scoped methods with explicit owner verification
    @Transactional(readOnly = true)
    public List<Workout> getWorkoutsForOwner(UUID ownerId) {
        if (ownerId == null) {
            throw new IllegalArgumentException("Owner ID must not be null");
        }
        return workoutRepository.findByUserIdOrderByWorkoutDateDesc(ownerId);
    }

    public Workout createWorkoutForOwner(Workout workout, User owner) {
        if (owner == null) {
            throw new IllegalArgumentException("Owner must not be null");
        }
        workout.setUser(owner);
        return workoutRepository.save(workout);
    }

    public Workout updateWorkoutForOwner(Workout workout, UUID ownerId) {
        if (workout.getId() == null) {
            throw new IllegalArgumentException("Workout ID must not be null for update");
        }
        if (ownerId == null) {
            throw new IllegalArgumentException("Owner ID must not be null");
        }
        Workout existing = workoutRepository.findByIdAndUserId(workout.getId(), ownerId)
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));

        existing.setTitle(workout.getTitle());
        existing.setWorkoutDate(workout.getWorkoutDate());
        existing.setDurationMinutes(workout.getDurationMinutes());
        existing.setNotes(workout.getNotes());
        return workoutRepository.save(existing);
    }

    public void deleteWorkoutForOwner(UUID workoutId, UUID ownerId) {
        if (ownerId == null) {
            throw new IllegalArgumentException("Owner ID must not be null");
        }
        Workout existing = workoutRepository.findByIdAndUserId(workoutId, ownerId)
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));
        workoutRepository.delete(existing);
    }
}
