// Relatively simple logger that supports log levels.
#import <Foundation/Foundation.h>

#undef LOG
#undef LOG_DEBUG
#undef LOG_INFO
#undef LOG_WARN
#undef LOG_ERROR

extern const int ERROR_LEVEL;
extern const int WARN_LEVEL;
extern const int INFO_LEVEL;
extern const int DEBUG_LEVEL;

void setupLogging(const char* path); 
void setLevel(const char* level);
double getTime(void);
bool _shouldLog(int level);
void _doLog(const char* level, const char* format, va_list args);

static inline void LOG_ERROR(const char* format, ...) __printflike(1, 2);
static inline void LOG_WARN(const char* format, ...) __printflike(1, 2);
static inline void LOG_INFO(const char* format, ...) __printflike(1, 2);
static inline void LOG_DEBUG(const char* format, ...) __printflike(1, 2);
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

static inline void LOG_INFO(const char* format, ...)
{
	if (_shouldLog(INFO_LEVEL))
	{
		va_list args;
		va_start(args, format);
		_doLog("INFO", format, args);
		va_end(args);
	}
}

static inline void LOG_DEBUG(const char* format, ...)
{
	if (_shouldLog(DEBUG_LEVEL))
	{
		va_list args;
		va_start(args, format);
		_doLog("DEBUG", format, args);
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
