import 'package:flutter/material.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _auth = AuthService.instance;

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _auth.user?.displayName ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отображаемое имя'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Имя или никнейм',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _auth.updateDisplayName(controller.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Имя обновлено')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Смена пароля'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Текущий пароль',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Введите текущий пароль' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль (от 8 симв.)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Введите новый пароль';
                  if (v.length < 8) return 'Минимум 8 символов';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Повторите новый пароль',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v != newPassController.text ? 'Пароли не совпадают' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await _auth.changePassword(
                  currentPassController.text,
                  newPassController.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Пароль изменён. Пожалуйста, войдите снова.')),
                  );
                  Navigator.of(context).pop();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Сменить'),
          ),
        ],
      ),
    );
  }

  void _showImportGuestDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт гостевых данных'),
        content: const Text(
          'Вы хотите скопировать ваши локальные тренировки из гостевого режима в текущий аккаунт? '
          'Существующие записи в аккаунте не будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final count = await _auth.copyGuestDataToAccount();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Успешно импортировано тренировок: $count')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка импорта: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  void _showServerSettings() {
    final client = _auth.apiClient;
    final controller = TextEditingController(text: client.baseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Адрес сервера'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Укажите адрес бэкенда для синхронизации:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://10.0.2.2:8080',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('10.0.2.2 (Эмулятор)'),
                  onPressed: () => controller.text = ApiClient.defaultEmulatorUrl,
                ),
                ActionChip(
                  label: const Text('localhost'),
                  onPressed: () => controller.text = ApiClient.defaultLocalhostUrl,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              await client.setBaseUrl(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Сервер установлен: ${client.baseUrl}')),
                );
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        final user = _auth.user;
        final isAuth = _auth.isAuthenticated;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Профиль'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_ethernet),
                tooltip: 'Настройки сервера',
                onPressed: _showServerSettings,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E222A) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      child: Text(
                        isAuth
                            ? (user?.presentationName.substring(0, 1).toUpperCase() ?? 'U')
                            : 'G',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAuth ? user!.presentationName : 'Гостевой режим',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAuth ? user!.email : 'Данные хранятся только локально',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          if (isAuth) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ID: ${user!.id.length > 8 ? user.id.substring(0, 8) : user.id}...',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (!isAuth) ...[
                // Guest mode prompt
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cloud_sync_outlined, color: Color(0xFF00E5FF)),
                          SizedBox(width: 8),
                          Text(
                            'Облачная синхронизация',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Войдите или зарегистрируйтесь, чтобы сохранять тренировки на сервере и не терять прогресс при смене устройства.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: const Text('Войти или создать аккаунт'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Account actions
                Text(
                  'НАСТРОЙКИ АККАУНТА',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 8),

                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Изменить имя'),
                  subtitle: Text(user?.displayName ?? 'Не указано'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showEditNameDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.lock_reset_outlined),
                  title: const Text('Сменить пароль'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showChangePasswordDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Импортировать гостевые данные'),
                  subtitle: const Text('Скопировать данные из гостевого режима'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showImportGuestDataDialog,
                ),
                const Divider(height: 32),

                Text(
                  'СЕССИИ И ВЫХОД',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 8),

                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.amber),
                  title: const Text('Выйти из аккаунта'),
                  subtitle: const Text('Завершить сессию на этом устройстве'),
                  onTap: () async {
                    final sm = ScaffoldMessenger.of(context);
                    await _auth.logout();
                    if (mounted) {
                      sm.showSnackBar(
                        const SnackBar(content: Text('Вы вышли из аккаунта')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.devices_other, color: Colors.redAccent),
                  title: const Text(
                    'Выйти со всех устройств',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  subtitle: const Text('Отозвать все активные refresh-токены'),
                  onTap: () async {
                    final sm = ScaffoldMessenger.of(context);
                    await _auth.logoutAll();
                    if (mounted) {
                      sm.showSnackBar(
                        const SnackBar(content: Text('Все сессии завершены')),
                      );
                    }
                  },
                ),
              ],

              const Divider(height: 32),

              // Server info
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Адрес сервера'),
                subtitle: Text(_auth.apiClient.baseUrl),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _showServerSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}
