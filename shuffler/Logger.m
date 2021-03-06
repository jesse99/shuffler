// Another approach is the Apple System Log facility, see http://boredzo.org/blog/archives/2008-01-20/why-asl
#import "Logger.h"

#import <sys/time.h>

const int ERROR_LEVEL   = 1;
const int WARN_LEVEL    = 2;
const int NORMAL_LEVEL  = 3;
const int VERBOSE_LEVEL = 4;

static FILE* _file;
static double _time;
static int _level;

static int _levelWidth;
static NSLock* _lock;

// This is kind of handy for timing stuff so we export it.
double getTime(void)
{
	struct timeval value;
	gettimeofday(&value, NULL);
	double secs = value.tv_sec + 1.0e-6*value.tv_usec;
	return secs - _time;
}

void setupLogging(const char* path)
{
	assert(_file == NULL);
	
	_file = fopen(path, "w");
	_time = getTime();
	_lock = [NSLock new];
	
	if (!_file)
	{
		syslog(LOG_ERR, "Couldn't open '%s': %s", path, strerror(errno));
	}
}

void setLevel(const char* level)
{
	[_lock lock];

	_level = 0;
	if (strcmp(level, "VERBOSE") == 0)
		_level = VERBOSE_LEVEL;
	else if (strcmp(level, "NORMAL") == 0)
		_level = NORMAL_LEVEL;
	else if (strcmp(level, "WARN") == 0)
		_level = WARN_LEVEL;
	else if (strcmp(level, "ERROR") == 0)
		_level = ERROR_LEVEL;
		
	if (_level == 0)
	{
		_level = NORMAL_LEVEL;
		[_lock unlock];
		LOG_ERROR("Attempt to set log level to bogus '%s'", level);
	}
	else
	{
		[_lock unlock];
	}
}

bool _shouldLog(int level)
{
	return _file != NULL && level <= _level;
}

void _doLog(const char* level, const char* format, va_list args)
{
	[_lock lock];
	fprintf(_file, "%.3f\t%-*s\t", getTime(), _levelWidth, level);
	vfprintf(_file, format, args);
	fprintf(_file, "\n");
	fflush(_file);
	[_lock unlock];
}

