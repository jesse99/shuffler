// Relatively simple logger that supports log levels.
#import <Foundation/Foundation.h>
#import <syslog.h>

extern const int ERROR_LEVEL;
extern const int WARN_LEVEL;
extern const int NORMAL_LEVEL;
extern const int VERBOSE_LEVEL;

void setupLogging(const char* path); 
void setLevel(const char* level);
double getTime(void);
bool _shouldLog(int level);
void _doLog(const char* level, const char* format, va_list args);

static inline void LOG_ERROR(const char* format, ...) __printflike(1, 2);
static inline void LOG_WARN(const char* format, ...) __printflike(1, 2);
static inline void LOG_NORMAL(const char* format, ...) __printflike(1, 2);
static inline void LOG_VERBOSE(const char* format, ...) __printflike(1, 2);
static inline void LOG(const char* format, ...) __printflike(1, 2);

static inline const char* STR(NSObject* object)
{
	return object.description.UTF8String;
}

static inline void LOG_ERROR(const char* format, ...)
{
	va_list args;
	va_start(args, format);
	_doLog("ERROR", format, args);
	va_end(args);
}

static inline void LOG_WARN(const char* format, ...)
{
	if (_shouldLog(WARN_LEVEL))
	{
		va_list args;
		va_start(args, format);
		_doLog("WARN", format, args);
		va_end(args);
	}
}

static inline void LOG_NORMAL(const char* format, ...)
{
	if (_shouldLog(NORMAL_LEVEL))
	{
		va_list args;
		va_start(args, format);
		_doLog("NORMAL", format, args);
		va_end(args);
	}
}

static inline void LOG_VERBOSE(const char* format, ...)
{
	if (_shouldLog(VERBOSE_LEVEL))
	{
		va_list args;
		va_start(args, format);
		_doLog("VERBOSE", format, args);
		va_end(args);
	}
}

static inline void LOG(const char* format, ...)
{
	va_list args;
	va_start(args, format);
	_doLog("     ", format, args);
	va_end(args);
}
