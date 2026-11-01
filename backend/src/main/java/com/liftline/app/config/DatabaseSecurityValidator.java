package com.liftline.app.config;

import org.springframework.beans.BeansException;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.beans.factory.config.ConfigurableListableBeanFactory;
import org.springframework.context.EnvironmentAware;
import org.springframework.core.Ordered;
import org.springframework.core.PriorityOrdered;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.Arrays;

@Component
public class DatabaseSecurityValidator implements BeanFactoryPostProcessor, EnvironmentAware, PriorityOrdered {

    private Environment environment;

    @Override
    public void setEnvironment(Environment environment) {
        this.environment = environment;
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }

    @Override
    public void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) throws BeansException {
        if (environment != null) {
            validateEnvironment(environment);
        }
    }

    public static void validateEnvironment(Environment env) {
        boolean isDevOrTest = Arrays.stream(env.getActiveProfiles())
                .anyMatch(p -> p.equalsIgnoreCase("dev") || p.equalsIgnoreCase("test"));

        String datasourceUrl = env.getProperty("spring.datasource.url", "");
        boolean isH2 = datasourceUrl.contains(":h2:");

        if (isDevOrTest || isH2) {
            return;
        }

        if (datasourceUrl.isBlank()) {
            throw new IllegalStateException(
                "Production database URL is not configured. Please specify the DB_URL environment variable. " +
                "For local development with in-memory H2, activate the 'dev' profile (--spring.profiles.active=dev)."
            );
        }

        String username = env.getProperty("spring.datasource.username", "");
        if (username.isBlank()) {
            throw new IllegalStateException(
                "Production database username is not configured. Please specify the DB_USERNAME environment variable."
            );
        }

        if ("root".equalsIgnoreCase(username.trim())) {
            throw new IllegalStateException(
                "Using the 'root' superuser for production database is prohibited for security reasons. " +
                "Please configure a dedicated database user with minimal necessary privileges via DB_USERNAME."
            );
        }

        String password = env.getProperty("spring.datasource.password", "");
        if (password.isBlank()) {
            throw new IllegalStateException(
                "Production database password is not configured or empty. Please specify the DB_PASSWORD environment variable."
            );
        }

        // Validate TLS for remote MySQL database connections
        String lowerUrl = datasourceUrl.toLowerCase();
        if (lowerUrl.startsWith("jdbc:mysql://")) {
            boolean isLocalhost = lowerUrl.contains("localhost") || lowerUrl.contains("127.0.0.1");
            if (!isLocalhost) {
                boolean hasExplicitSslDisabled = lowerUrl.contains("usessl=false") || lowerUrl.contains("sslmode=disabled");
                boolean hasVerifiedSsl = lowerUrl.contains("sslmode=verify_identity")
                                      || lowerUrl.contains("sslmode=verify_ca")
                                      || (lowerUrl.contains("usessl=true") && !lowerUrl.contains("allowpublickeyretrieval=true"));

                if (hasExplicitSslDisabled || !hasVerifiedSsl) {
                    throw new IllegalStateException(
                        "Remote MySQL connection requires verified TLS. " +
                        "Configure DB_URL with sslMode=VERIFY_IDENTITY or sslMode=VERIFY_CA."
                    );
                }
            }
        }
    }
}
