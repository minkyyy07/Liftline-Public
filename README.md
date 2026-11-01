# Liftline

A fitness tracker product codebase with Flutter client and Spring Boot backend.

## Architecture & Current Status

### Storage & Synchronization Status (Important)
- **Client (Flutter)**: Currently stores all workout and nutrition records in a **local SQLite database** (`liftline.db`).
- **Backend (Spring Boot)**: Currently implements **authentication only** (`/api/auth/register`, `/api/auth/login`). There are **no workout or nutrition REST API endpoints** implemented on the backend.
- **Data Synchronization**: Cloud synchronization across devices is **NOT implemented**. Flutter does not send workout or nutrition data to the backend.

#### Architectural Blocker & Proposal for Account / Cloud Sync:
If cross-device synchronization and user accounts for workouts and nutrition are required, the following architectural steps must be implemented:
1. **REST Endpoints for Workouts & Nutrition**: Implement secure controllers on the backend mapped to `WorkoutService` (and a future `NutritionService`), ensuring all operations derive the user identity solely from the JWT Bearer token (never accepting `userId` in request parameters).
2. **Sync Protocol & Conflict Resolution**: Choose between an offline-first synchronization strategy (e.g. tracking `updated_at`, tombstone records for deletions, and Last-Write-Wins / CRDT conflict resolution) or a client-server API sync queue.
3. **Flutter Network Layer**: Add an HTTP repository layer in Flutter that authenticates against `/api/auth`, stores JWT securely in `flutter_secure_storage` / `shared_preferences`, and synchronizes local SQLite entries with backend endpoints.

---

## Structure

- `backend/` — Spring Boot 3 + Java 17+ REST API with JWT authentication, Flyway SQL migrations, and owner-scoped `WorkoutService`.
- `flutter_app/` — Flutter application for iOS, Android, and Desktop with local SQLite storage.

---

## Implemented Features

### Flutter Client
- Local SQLite database layer (`liftline.db`) for workouts, exercises, sets, nutrition entries, and goals.
- **Robust Input Validation (`InputValidators`)**:
  - Calorie and repetition counts validated as integers (reps strictly > 0, calories >= 0).
  - Weights and macronutrients (protein, fat, carbs) validated as finite non-negative numbers (>= 0.0), with locale normalization for commas (`12,5` -> `12.5`).
  - Workout duration validated as a strictly positive integer (> 0).
  - Forms use Material `Form` + `TextFormField` with clear error messages. Forms stay open and block submission until all invalid fields are corrected.
  - Invalid input is **never silently converted to `0` or `0.0`**.
  - Empty optional fields (e.g., portion text, optional macros) are handled explicitly and safely.
  - Unit tests for all validation and parsing edge cases in `flutter_app/test/validators_test.dart`.

### Backend
- **Authentication Endpoints**:
  - Registration (`POST /api/auth/register`) with BCrypt password hashing.
  - Login (`POST /api/auth/login`) returning HMAC-SHA256 JWT tokens.
- **Password Security & BCrypt UTF-8 Byte Limit**:
  - Validates passwords between 8 characters and **72 bytes in UTF-8** (`@BcryptPassword`).
  - Prevents standard BCrypt silent truncation past 72 bytes and avoids server exceptions on long passwords.
  - *Migration Strategy for Existing Accounts*: If an existing system permitted passwords > 72 bytes (which standard BCrypt truncated at 72 bytes during hashing), two options are available:
    1. Pre-hash passwords using SHA-256 before BCrypt (`bcrypt(sha256(password))`) for all new and migrated accounts.
    2. During a transition period, authenticate logins by truncating to 72 bytes if matching the legacy hash, and prompt the user to update their password within the valid byte limit.
- **Concurrency & Race Condition Protection**:
  - Registration is protected against simultaneous duplicate email registration: catches unique constraint violations (`DataIntegrityViolationException`) and returns HTTP 400 Bad Request (`{"error": "Email already registered"}`) rather than HTTP 500.
- **Data Ownership Boundaries (`WorkoutService`)**:
  - All operations are strictly owner-scoped. The service derives user identity directly from Spring Security's `SecurityContextHolder` (`getCurrentUserWorkouts`, `createWorkoutForCurrentUser`, `updateWorkoutForCurrentUser`, `deleteWorkoutForCurrentUser`) or enforces an explicit `ownerId` matched against the database (`findByIdAndUserId`).
  - Client requests cannot pass arbitrary `userId` to manipulate other users' data.
  - Unauthorized access attempts throw `AccessDeniedException`.
- **Database Configuration & Production Hardening**:
  - Insecure production fallbacks (such as default `root` user, empty password, or unencrypted MySQL) are completely removed.
  - `DatabaseSecurityValidator` verifies on startup that required production parameters are set, rejecting the `root` user and enforcing verified TLS for remote MySQL.
  - Development profile (`dev`) remains fully functional for zero-config local development using in-memory H2 in MySQL mode.

---

## Security & Secret Management

### JWT Secret (`JWT_SECRET`)
- `JWT_SECRET` must be supplied via environment variable and must be at least **32 bytes (256 bits)** long.
- **Important**: The 32-byte length check is a *minimum technical requirement* for HMAC-SHA256, but **length alone does not guarantee security**. The secret must be generated using a cryptographically secure pseudo-random number generator (CSPRNG), for example:
  ```bash
  openssl rand -hex 32
  # or
  openssl rand -base64 32
  ```
- **Never commit real secrets to the repository.**

### Database Security
- **Local Dev**: Use the `dev` profile with in-memory H2.
- **Remote Production MySQL**:
  - Do not use the `root` administrative superuser. Create a dedicated database user with minimal necessary privileges (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `ALTER`, `INDEX`).
  - Require verified TLS by appending `sslMode=VERIFY_IDENTITY` or `sslMode=VERIFY_CA` to `DB_URL`.

---

## Local Run

### Prerequisites
- JDK 17+ (JDK 21 or 24 supported)
- Maven 3.8+

### Option 1: Local Development with In-Memory H2 (`dev` profile)

Build and run using the packaged JAR (recommended):

```bash
cd backend
mvn clean package -DskipTests
JWT_SECRET="<generate-random-secret-at-least-32-bytes>" java -jar target/backend-0.1.0.jar --spring.profiles.active=dev
```

Or run via Maven Spring Boot plugin:

```bash
cd backend
JWT_SECRET="<generate-random-secret-at-least-32-bytes>" mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

### Option 2: Run with MySQL

Ensure MySQL is running with TLS and provide credentials via environment variables:

```bash
cd backend
mvn clean package -DskipTests
JWT_SECRET="<generate-random-secret-at-least-32-bytes>" \
DB_URL="jdbc:mysql://localhost:3306/liftline?createDatabaseIfNotExist=true&sslMode=PREFERRED&serverTimezone=UTC" \
DB_USERNAME="liftline_app" \
DB_PASSWORD="your-strong-db-password" \
java -jar target/backend-0.1.0.jar
```

For remote MySQL hosts (e.g., AWS RDS / cloud):
```bash
DB_URL="jdbc:mysql://db.example.com:3306/liftline?sslMode=VERIFY_IDENTITY&serverTimezone=UTC"
```

Supported environment variables:
- `JWT_SECRET` — JWT HMAC signing key (minimum 32 bytes, required)
- `JWT_EXPIRATION_MS` — Token expiration in ms (default: 86400000 / 24h)
- `DB_URL` — JDBC connection URL (required in production)
- `DB_USERNAME` — Database user (required in production, non-root)
- `DB_PASSWORD` — Database password (required in production)
- `DB_DRIVER` — Driver class name (default: `com.mysql.cj.jdbc.Driver`)

---

## Testing & Verification

### Backend Tests

Execute the automated test suite with:

```bash
mvn -f backend/pom.xml clean test
```

Or from the `backend/` directory:

```bash
cd backend
mvn clean test
```

### Test Suite Coverage (28 automated tests):
1. **`AuthAndIsolationTests` (10 tests)**:
   - Valid registration and BCrypt password hash verification.
   - Valid login, JWT issuance, and claim parsing.
   - Password boundary tests: < 8 chars (rejected), 8 chars (accepted), 72 ASCII bytes (accepted), 73 ASCII bytes (rejected), multi-byte UTF-8 > 72 bytes (rejected), multi-byte UTF-8 <= 72 bytes (accepted).
   - Duplicate email registration rejection with case insensitivity.
   - Concurrent registration race condition: 10 parallel threads simultaneously registering the same email — exactly 1 succeeds (200), remaining 9 receive 400 Bad Request, zero 500 errors.
   - Invalid request payloads (email format, blank fields).
   - Login with wrong password (401) and non-existent user (401).
   - JWT tampering and claims validation.
   - Protected endpoint authorization filter.
2. **`WorkoutServiceOwnershipTest` (5 tests)**:
   - User B cannot read User A's workout (`AccessDeniedException`).
   - User B cannot update User A's workout (`AccessDeniedException`).
   - User B cannot delete User A's workout (`AccessDeniedException`).
   - Owner can read, update, and delete their own workout.
   - Owner-scoped programmatic methods reject mismatched `ownerId`.
3. **`DatabaseSecurityValidatorTest` (8 tests)**:
   - Dev and test profiles bypass production checks.
   - In-memory H2 URLs bypass production checks.
   - Missing `DB_URL`, `DB_USERNAME`, or `DB_PASSWORD` in production throws `IllegalStateException`.
   - Prohibits `root` username in production.
   - Rejects unencrypted remote MySQL connections (`useSSL=false` / `sslMode=disabled`).
   - Accepts remote MySQL with verified TLS (`sslMode=VERIFY_IDENTITY`).
4. **`JwtSecretValidationTest` (5 tests)**:
   - Rejects null, blank, and < 32-byte JWT secrets with descriptive messages.
   - Accepts >= 32-byte secrets.
   - Constructor validation in `JwtService`.

---

## Verification Status

- **Backend Compile**: Passed (`mvn -f backend/pom.xml compile`)
- **Backend Tests**: Passed (`mvn -f backend/pom.xml clean test` — 28/28 tests passed)
- **Local Startup Verification**: Verified with `dev` profile via packaged JAR and curl tests.
- **Production Startup Security**: Verified that production startup halts with clear messages if `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, or TLS settings are missing or insecure.
- **Flutter Build / Analyzer / Tests**: **Not executed in this environment** because neither Flutter SDK nor Dart CLI is installed on this machine (`flutter: command not found`, `dart: command not found`). The validation logic and test files (`flutter_app/lib/validators.dart`, `flutter_app/test/validators_test.dart`) have been implemented following Flutter and Dart SDK conventions.
