package com.liftline.app.service;

import com.liftline.app.dto.CreateWorkoutRequest;
import com.liftline.app.dto.SetEntryDto;
import com.liftline.app.dto.UpdateWorkoutRequest;
import com.liftline.app.dto.WorkoutDto;
import com.liftline.app.dto.WorkoutExerciseDto;
import com.liftline.app.entity.SetEntry;
import com.liftline.app.entity.User;
import com.liftline.app.entity.Workout;
import com.liftline.app.entity.WorkoutExercise;
import com.liftline.app.repository.SetEntryRepository;
import com.liftline.app.repository.UserRepository;
import com.liftline.app.repository.WorkoutExerciseRepository;
import com.liftline.app.repository.WorkoutRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

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
    public Page<Workout> getCurrentUserWorkouts(Pageable pageable) {
        User user = getAuthenticatedUser();
        return workoutRepository.findByUserIdOrderByWorkoutDateDesc(user.getId(), pageable);
    }

    @Transactional(readOnly = true)
    public List<WorkoutDto> getCurrentUserWorkoutsDto(Pageable pageable) {
        User user = getAuthenticatedUser();
        Page<Workout> page = workoutRepository.findByUserIdOrderByWorkoutDateDesc(user.getId(), pageable);
        return page.getContent().stream().map(this::toDto).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public WorkoutDto getWorkoutDtoByIdForCurrentUser(UUID workoutId) {
        Workout workout = getWorkoutByIdForCurrentUser(workoutId);
        return toDto(workout);
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

    public Workout createWorkoutFromRequest(CreateWorkoutRequest request) {
        User user = getAuthenticatedUser();
        Workout workout = new Workout();
        workout.setUser(user);
        workout.setWorkoutDate(request.getWorkoutDate());
        workout.setTitle(request.getTitle().trim());
        workout.setDurationMinutes(request.getDurationMinutes());
        workout.setNotes(request.getNotes());

        if (request.getExercises() != null) {
            for (WorkoutExerciseDto weDto : request.getExercises()) {
                WorkoutExercise exercise = new WorkoutExercise();
                exercise.setWorkout(workout);
                exercise.setExerciseName(weDto.getExerciseName().trim());
                exercise.setSortOrder(weDto.getSortOrder() != null ? weDto.getSortOrder() : 0);

                if (weDto.getSets() != null) {
                    for (SetEntryDto seDto : weDto.getSets()) {
                        SetEntry setEntry = new SetEntry();
                        setEntry.setExercise(exercise);
                        setEntry.setSetNumber(seDto.getSetNumber());
                        setEntry.setWeightKg(seDto.getWeightKg());
                        setEntry.setReps(seDto.getReps());
                        setEntry.setCompleted(seDto.getCompleted() != null ? seDto.getCompleted() : true);
                        setEntry.setRpe(seDto.getRpe());
                        setEntry.setSetType(seDto.getSetType());
                        setEntry.setRestSeconds(seDto.getRestSeconds());
                        setEntry.setNotes(seDto.getNotes());
                        exercise.getSets().add(setEntry);
                    }
                }
                workout.getExercises().add(exercise);
            }
        }
        return workoutRepository.save(workout);
    }

    public Workout updateWorkoutFromRequest(UUID workoutId, UpdateWorkoutRequest request) {
        User user = getAuthenticatedUser();
        Workout existing = workoutRepository.findByIdAndUserId(workoutId, user.getId())
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));

        existing.setTitle(request.getTitle().trim());
        existing.setWorkoutDate(request.getWorkoutDate());
        existing.setDurationMinutes(request.getDurationMinutes());
        existing.setNotes(request.getNotes());

        existing.getExercises().clear();
        if (request.getExercises() != null) {
            for (WorkoutExerciseDto weDto : request.getExercises()) {
                WorkoutExercise exercise = new WorkoutExercise();
                exercise.setWorkout(existing);
                exercise.setExerciseName(weDto.getExerciseName().trim());
                exercise.setSortOrder(weDto.getSortOrder() != null ? weDto.getSortOrder() : 0);

                if (weDto.getSets() != null) {
                    for (SetEntryDto seDto : weDto.getSets()) {
                        SetEntry setEntry = new SetEntry();
                        setEntry.setExercise(exercise);
                        setEntry.setSetNumber(seDto.getSetNumber());
                        setEntry.setWeightKg(seDto.getWeightKg());
                        setEntry.setReps(seDto.getReps());
                        setEntry.setCompleted(seDto.getCompleted() != null ? seDto.getCompleted() : true);
                        setEntry.setRpe(seDto.getRpe());
                        setEntry.setSetType(seDto.getSetType());
                        setEntry.setRestSeconds(seDto.getRestSeconds());
                        setEntry.setNotes(seDto.getNotes());
                        exercise.getSets().add(setEntry);
                    }
                }
                existing.getExercises().add(exercise);
            }
        }
        return workoutRepository.save(existing);
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

    public WorkoutDto toDto(Workout workout) {
        WorkoutDto dto = new WorkoutDto();
        dto.setId(workout.getId());
        dto.setWorkoutDate(workout.getWorkoutDate());
        dto.setTitle(workout.getTitle());
        dto.setDurationMinutes(workout.getDurationMinutes());
        dto.setNotes(workout.getNotes());
        dto.setCreatedAt(workout.getCreatedAt());
        dto.setUpdatedAt(workout.getUpdatedAt());

        if (workout.getExercises() != null) {
            List<WorkoutExerciseDto> exerciseDtos = workout.getExercises().stream().map(we -> {
                WorkoutExerciseDto wed = new WorkoutExerciseDto();
                wed.setId(we.getId());
                wed.setExerciseName(we.getExerciseName());
                wed.setSortOrder(we.getSortOrder());
                if (we.getSets() != null) {
                    List<SetEntryDto> setDtos = we.getSets().stream().map(se -> {
                        SetEntryDto sed = new SetEntryDto();
                        sed.setId(se.getId());
                        sed.setSetNumber(se.getSetNumber());
                        sed.setWeightKg(se.getWeightKg());
                        sed.setReps(se.getReps());
                        sed.setCompleted(se.getCompleted());
                        sed.setRpe(se.getRpe());
                        sed.setSetType(se.getSetType());
                        sed.setRestSeconds(se.getRestSeconds());
                        sed.setNotes(se.getNotes());
                        return sed;
                    }).collect(Collectors.toList());
                    wed.setSets(setDtos);
                }
                return wed;
            }).collect(Collectors.toList());
            dto.setExercises(exerciseDtos);
        }
        return dto;
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
