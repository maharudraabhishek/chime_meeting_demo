package com.example.chimemeeting.chime

import com.amazonaws.services.chime.sdk.meetings.utils.logger.ConsoleLogger
import com.amazonaws.services.chime.sdk.meetings.utils.logger.LogLevel
import com.amazonaws.services.chime.sdk.meetings.utils.logger.Logger

/**
 * Delegates SDK logging only after removing transient attendee credentials.
 *
 * The active JoinToken is held only for redaction and is cleared with the
 * session. Bridge arguments and REST credentials are never logged.
 */
internal class SafeChimeLogger(
    private val delegate: Logger = ConsoleLogger(LogLevel.WARN),
) : Logger {
    private val sensitiveValues = mutableSetOf<String>()

    /** Registers one ephemeral credential that must be redacted from SDK logs. */
    @Synchronized
    fun registerSensitiveValue(value: String) {
        if (value.isNotBlank()) sensitiveValues.add(value)
    }

    /** Clears all ephemeral redaction values when the meeting session ends. */
    @Synchronized
    fun clearSensitiveValues() {
        sensitiveValues.clear()
    }

    /** Delegates a sanitized debug message. */
    override fun debug(tag: String, msg: String) = delegate.debug(tag, sanitize(msg))

    /** Delegates a sanitized informational message. */
    override fun info(tag: String, msg: String) = delegate.info(tag, sanitize(msg))

    /** Delegates a sanitized warning message. */
    override fun warn(tag: String, msg: String) = delegate.warn(tag, sanitize(msg))

    /** Delegates a sanitized error message. */
    override fun error(tag: String, msg: String) = delegate.error(tag, sanitize(msg))

    /** Delegates a sanitized verbose message. */
    override fun verbose(tag: String, msg: String) = delegate.verbose(tag, sanitize(msg))

    /** Returns the active delegated SDK log level. */
    override fun getLogLevel(): LogLevel = delegate.getLogLevel()

    /** Updates the delegated SDK log level. */
    override fun setLogLevel(level: LogLevel) = delegate.setLogLevel(level)

    /** Replaces every registered transient credential before log delegation. */
    @Synchronized
    private fun sanitize(message: String): String = sensitiveValues.fold(message) { safe, secret ->
        safe.replace(secret, REDACTED)
    }

    /** Redaction marker shared by all sanitized messages. */
    private companion object {
        const val REDACTED = "[REDACTED]"
    }
}

