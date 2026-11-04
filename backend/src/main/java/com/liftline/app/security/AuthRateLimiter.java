package com.liftline.app.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class AuthRateLimiter {

    @Value("${auth.rate-limit.enabled:true}")
    private boolean enabled;

    @Value("${auth.rate-limit.max-requests:30}")
    private int maxRequests;

    @Value("${auth.rate-limit.window-seconds:60}")
    private int windowSeconds;

    private final Map<String, Deque<Instant>> requestTimestamps = new ConcurrentHashMap<>();

    public synchronized boolean tryAcquire(String key) {
        if (!enabled) {
            return true;
        }

        Instant now = Instant.now();
        Instant cutoff = now.minusSeconds(windowSeconds);

        Deque<Instant> timestamps = requestTimestamps.computeIfAbsent(key, k -> new ArrayDeque<>());

        // Evict expired timestamps
        while (!timestamps.isEmpty() && timestamps.peekFirst().isBefore(cutoff)) {
            timestamps.pollFirst();
        }

        if (timestamps.size() >= maxRequests) {
            return false;
        }

        timestamps.addLast(now);
        return true;
    }

    public synchronized void reset() {
        requestTimestamps.clear();
    }

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }
    public void setMaxRequests(int maxRequests) { this.maxRequests = maxRequests; }
}
