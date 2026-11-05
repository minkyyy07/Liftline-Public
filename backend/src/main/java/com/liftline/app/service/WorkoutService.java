package com.liftline.app.service;

import com.liftline.app.dto.CreateWorkoutRequest;
import com.liftline.app.dto.PartialDto;
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
import jakarta.persistence.EntityExistsException;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@Transactional
public class WorkoutService {
    static final String DEFAULT_STATUS = "finished";

    private final WorkoutRepository workoutRepository;
    private final WorkoutExerciseRepository workoutExerciseRepository;
    private final SetEntryRepository setEntryRepository;
    private final UserRepository userRepository;

    @PersistenceContext
    private EntityManager entityManager;

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
        return workoutRepository.findByUserIdOrderByWorkoutDateDescIdAsc(user.getId(), pageable);
    }

    @Transactional(readOnly = true)
    public List<WorkoutDto> getCurrentUserWorkoutsDto(Pageable pageable) {
        User user = getAuthenticatedUser();
        Page<Workout> page = workoutRepository.findByUserIdOrderByWorkoutDateDescIdAsc(user.getId(), pageable);
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

    public WorkoutDto createWorkoutDtoFromRequest(CreateWorkoutRequest request) {
        Workout created = createWorkoutFromRequest(request);
        return toDto(created);
    }

    public WorkoutDto updateWorkoutDtoFromRequest(UUID workoutId, UpdateWorkoutRequest request) {
        Workout updated = updateWorkoutFromRequest(workoutId, request);
        return toDto(updated);
    }

    public Workout createWorkoutFromRequest(CreateWorkoutRequest request) {
        User user = getAuthenticatedUser();
        if (request.getId() != null) {
            Optional<Workout> existing = workoutRepository.findByIdAndUserId(request.getId(), user.getId());
            if (existing.isPresent()) {
                validateNestedIds(request.getExercises(), indexExercises(existing.get()));
                // Idempotent: return already created workout
                return existing.get();
            }
            if (workoutRepository.existsById(request.getId())) {
                // Client UUID already belongs to another account: never take it over
                throw new AccessDeniedException("Workout not found or access denied");
            }
        }
        validateNestedIds(request.getExercises(), Map.of());
        Workout workout = new Workout();
        workout.setUser(user);
        if (request.getId() != null) {
            workout.setId(request.getId());
        }
        workout.setWorkoutDate(request.getWorkoutDate());
        workout.setTitle(request.getTitle().trim());
        workout.setDurationMinutes(request.getDurationMinutes());
        workout.setNotes(request.getNotes());
        // Requests without a status come from legacy clients: historical workouts are finished.
        workout.setStatus(request.getStatus() != null ? request.getStatus() : DEFAULT_STATUS);
        workout.setStartedAt(request.getStartedAtUtc());
        workout.setFinishedAt(request.getFinishedAtUtc());
        workout.getExercises().addAll(buildExercises(workout, request.getExercises(), Map.of()));
        return persistAndFlush(workout);
    }

    public Workout updateWorkoutFromRequest(UUID workoutId, UpdateWorkoutRequest request) {
        User user = getAuthenticatedUser();
        Workout existing = workoutRepository.findByIdAndUserId(workoutId, user.getId())
                .orElseThrow(() -> new AccessDeniedException("Workout not found or access denied"));

        // Conflict check: optimistic locking via exact revision (version) or clientUpdatedAt
        if (request.getVersion() != null && existing.getVersion() != null) {
            if (!request.getVersion().equals(existing.getVersion())) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Workout conflict: newer version exists on server");
            }
        } else if (request.getClientUpdatedAt() != null && existing.getUpdatedAt() != null) {
            if (existing.getUpdatedAt().isAfter(request.getClientUpdatedAt())) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Workout conflict: newer version exists on server");
            }
        }

        if (request.isPresent("exercises")) {
            validateNestedIds(request.getExercises(), indexExercises(existing));
        }

        existing.setTitle(request.getTitle().trim());
        existing.setWorkoutDate(request.getWorkoutDate());
        // Fields missing from the payload keep their stored value; an explicit null clears optional ones.
        if (request.isPresent("durationMinutes")) {
            existing.setDurationMinutes(request.getDurationMinutes());
        }
        if (request.isPresent("notes")) {
            existing.setNotes(request.getNotes());
        }
        // status is NOT NULL: a null value is treated as "not provided".
        if (request.isPresent("status") && request.getStatus() != null) {
            existing.setStatus(request.getStatus());
        }
        if (request.isPresent("startedAtUtc")) {
            existing.setStartedAt(request.getStartedAtUtc());
        }
        if (request.isPresent("finishedAtUtc")) {
            existing.setFinishedAt(request.getFinishedAtUtc());
        }

        if (request.isPresent("exercises")) {
            // Upsert by id: rows that are still in the payload are updated in place,
            // rows missing from it are removed (orphanRemoval). Nothing is recreated.
            List<WorkoutExercise> next = buildExercises(existing, request.getExercises(), indexExercises(existing));
            existing.getExercises().clear();
            existing.getExercises().addAll(next);
        }
        // Flush so @Version is bumped before the response is built: the client sends the
        // revision it receives back on its next upload, and a stale one would be a false 409.
        // Child-only changes must also participate in the workout's optimistic lock.
        existing.setUpdatedAt(Instant.now());
        return persistAndFlush(existing);
    }

    private Workout persistAndFlush(Workout workout) {
        try {
            // Never merge client-assigned IDs: a concurrent insert must fail at the PK,
            // not turn a new child into an update of the row that won the race.
            entityManager.persist(workout);
            workoutRepository.flush();
            return workout;
        } catch (EntityExistsException | DataIntegrityViolationException ex) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Workout conflict: ID already in use", ex);
        }
    }

    private void validateNestedIds(List<WorkoutExerciseDto> exercises, Map<UUID, WorkoutExercise> previous) {
        if (exercises == null) {
            return;
        }
        Set<UUID> seen = new HashSet<>();
        for (WorkoutExerciseDto exercise : exercises) {
            if (exercise == null) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid nested workout entry");
            }
            UUID exerciseId = exercise.getId();
            checkUniqueNestedId(exerciseId, seen);
            WorkoutExercise stored = exerciseId == null ? null : previous.get(exerciseId);
            if (exerciseId != null && stored == null && workoutExerciseRepository.existsById(exerciseId)) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Workout conflict: ID already in use");
            }
            Map<UUID, SetEntry> previousSets = stored == null ? Map.of() : indexSets(stored);
            if (exercise.getSets() == null) {
                continue;
            }
            for (SetEntryDto set : exercise.getSets()) {
                if (set == null) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid nested workout entry");
                }
                UUID setId = set.getId();
                checkUniqueNestedId(setId, seen);
                if (setId != null && !previousSets.containsKey(setId) && setEntryRepository.existsById(setId)) {
                    throw new ResponseStatusException(HttpStatus.CONFLICT, "Workout conflict: ID already in use");
                }
            }
        }
    }

    private static void checkUniqueNestedId(UUID id, Set<UUID> seen) {
        if (id != null && !seen.add(id)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Duplicate nested workout ID");
        }
    }

    /**
     * Builds exercises from DTOs. A DTO whose id matches an entity in {@code previous} updates
     * that entity in place: fields absent from the payload keep their stored value.
     */
    private List<WorkoutExercise> buildExercises(Workout owner, List<WorkoutExerciseDto> dtos,
                                                 Map<UUID, WorkoutExercise> previous) {
        List<WorkoutExercise> result = new ArrayList<>();
        if (dtos == null) {
            return result;
        }
        for (WorkoutExerciseDto dto : dtos) {
            WorkoutExercise prev = dto.getId() == null ? null : previous.get(dto.getId());
            boolean hasPrev = prev != null;
            WorkoutExercise exercise = hasPrev ? prev : new WorkoutExercise();
            if (!hasPrev) {
                if (dto.getId() != null) {
                    exercise.setId(dto.getId());
                }
                exercise.setCreatedAt(Instant.now());
                exercise.setUpdatedAt(Instant.now());
            }
            exercise.setWorkout(owner);
            exercise.setExerciseName(dto.getExerciseName().trim());
            exercise.setSortOrder(dto.getSortOrder() != null ? dto.getSortOrder() : 0);
            exercise.setExerciseRefId(pick(hasPrev, dto, "exerciseRefId", dto.getExerciseRefId(), exercise.getExerciseRefId()));
            exercise.setNotes(pick(hasPrev, dto, "notes", dto.getNotes(), exercise.getNotes()));
            exercise.setPlanSets(pick(hasPrev, dto, "planSets", dto.getPlanSets(), exercise.getPlanSets()));
            exercise.setPlanRepMin(pick(hasPrev, dto, "planRepMin", dto.getPlanRepMin(), exercise.getPlanRepMin()));
            exercise.setPlanRepMax(pick(hasPrev, dto, "planRepMax", dto.getPlanRepMax(), exercise.getPlanRepMax()));
            exercise.setPlanRir(pick(hasPrev, dto, "planRir", dto.getPlanRir(), exercise.getPlanRir()));
            exercise.setPlanRestSec(pick(hasPrev, dto, "planRestSec", dto.getPlanRestSec(), exercise.getPlanRestSec()));

            if (!hasPrev || dto.isPresent("sets")) {
                List<SetEntry> nextSets = buildSets(exercise, dto.getSets(), indexSets(exercise));
                exercise.getSets().clear();
                exercise.getSets().addAll(nextSets);
            }
            result.add(exercise);
        }
        return result;
    }

    private List<SetEntry> buildSets(WorkoutExercise owner, List<SetEntryDto> dtos, Map<UUID, SetEntry> previous) {
        List<SetEntry> result = new ArrayList<>();
        if (dtos == null) {
            return result;
        }
        for (SetEntryDto dto : dtos) {
            SetEntry prev = dto.getId() == null ? null : previous.get(dto.getId());
            boolean hasPrev = prev != null;
            SetEntry set = hasPrev ? prev : new SetEntry();
            if (!hasPrev) {
                if (dto.getId() != null) {
                    set.setId(dto.getId());
                }
                set.setCreatedAt(Instant.now());
                set.setUpdatedAt(Instant.now());
            }
            set.setExercise(owner);
            set.setSetNumber(dto.getSetNumber());
            set.setWeightKg(pick(hasPrev, dto, "weightKg", dto.getWeightKg(), set.getWeightKg()));
            set.setReps(pick(hasPrev, dto, "reps", dto.getReps(), set.getReps()));
            Boolean completedIncoming = dto.getCompleted() != null ? dto.getCompleted() : Boolean.TRUE;
            set.setCompleted(pick(hasPrev, dto, "completed", completedIncoming, set.getCompleted()));
            set.setRpe(pick(hasPrev, dto, "rpe", dto.getRpe(), set.getRpe()));
            set.setSetType(pick(hasPrev, dto, "setType", dto.getSetType(), set.getSetType()));
            set.setRestSeconds(pick(hasPrev, dto, "restSeconds", dto.getRestSeconds(), set.getRestSeconds()));
            set.setNotes(pick(hasPrev, dto, "notes", dto.getNotes(), set.getNotes()));
            set.setRir(pick(hasPrev, dto, "rir", dto.getRir(), set.getRir()));
            set.setCompletedAt(pick(hasPrev, dto, "completedAtUtc", dto.getCompletedAtUtc(), set.getCompletedAt()));
            result.add(set);
        }
        return result;
    }

    /** Returns the incoming value when there is no stored entity, or when the field was sent. */
    private static <T> T pick(boolean hasPrevious, PartialDto dto, String field, T incoming, T stored) {
        return (!hasPrevious || dto.isPresent(field)) ? incoming : stored;
    }

    private static Map<UUID, WorkoutExercise> indexExercises(Workout workout) {
        Map<UUID, WorkoutExercise> index = new HashMap<>();
        for (WorkoutExercise ex : workout.getExercises()) {
            index.put(ex.getId(), ex);
        }
        return index;
    }

    private static Map<UUID, SetEntry> indexSets(WorkoutExercise exercise) {
        Map<UUID, SetEntry> index = new HashMap<>();
        for (SetEntry set : exercise.getSets()) {
            index.put(set.getId(), set);
        }
        return index;
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
        Optional<Workout> workoutOpt = workoutRepository.findById(workoutId);
        if (workoutOpt.isPresent()) {
            Workout workout = workoutOpt.get();
            if (!workout.getUser().getId().equals(user.getId())) {
                throw new AccessDeniedException("Workout not found or access denied");
            }
            workoutRepository.delete(workout);
        }
    }

    public WorkoutDto toDto(Workout workout) {
        WorkoutDto dto = new WorkoutDto();
        dto.setId(workout.getId());
        dto.setWorkoutDate(workout.getWorkoutDate());
        dto.setTitle(workout.getTitle());
        dto.setDurationMinutes(workout.getDurationMinutes());
        dto.setNotes(workout.getNotes());
        dto.setStatus(workout.getStatus());
        dto.setStartedAtUtc(workout.getStartedAt());
        dto.setFinishedAtUtc(workout.getFinishedAt());
        dto.setCreatedAt(workout.getCreatedAt());
        dto.setUpdatedAt(workout.getUpdatedAt());
        dto.setVersion(workout.getVersion());

        if (workout.getExercises() != null) {
            List<WorkoutExerciseDto> exerciseDtos = workout.getExercises().stream()
                    .sorted(Comparator.comparing(WorkoutExercise::getSortOrder, Comparator.nullsLast(Comparator.naturalOrder())))
                    .map(we -> {
                WorkoutExerciseDto wed = new WorkoutExerciseDto();
                wed.setId(we.getId());
                wed.setExerciseName(we.getExerciseName());
                wed.setSortOrder(we.getSortOrder());
                wed.setExerciseRefId(we.getExerciseRefId());
                wed.setNotes(we.getNotes());
                wed.setPlanSets(we.getPlanSets());
                wed.setPlanRepMin(we.getPlanRepMin());
                wed.setPlanRepMax(we.getPlanRepMax());
                wed.setPlanRir(we.getPlanRir());
                wed.setPlanRestSec(we.getPlanRestSec());
                if (we.getSets() != null) {
                    List<SetEntryDto> setDtos = we.getSets().stream()
                            .sorted(Comparator.comparing(SetEntry::getSetNumber, Comparator.nullsLast(Comparator.naturalOrder())))
                            .map(se -> {
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
                        sed.setRir(se.getRir());
                        sed.setCompletedAtUtc(se.getCompletedAt());
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
        Optional<Workout> workoutOpt = workoutRepository.findById(workoutId);
        if (workoutOpt.isPresent()) {
            Workout workout = workoutOpt.get();
            if (!workout.getUser().getId().equals(ownerId)) {
                throw new AccessDeniedException("Workout not found or access denied");
            }
            workoutRepository.delete(workout);
        }
    }
}
