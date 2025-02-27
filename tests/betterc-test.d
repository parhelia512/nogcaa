module betterc_test;

import bcaa;

import core.stdc.stdio;

version (Windows) {
    struct timeval {
        long tv_sec;
        long tv_usec;
    }

    extern (C) int gettimeofday(timeval* tp, void* tzp) @nogc nothrow {
        import core.sys.windows.winbase : FILETIME, SYSTEMTIME;

        /** This magic number is the number of 100 nanosecond intervals since January 1, 1601 (UTC)
          * until 00:00:00 January 1, 1970
          */
        static const ulong EPOCH = 116_444_736_000_000_000UL;

        winbase.SYSTEMTIME system_time;
        winbase.FILETIME file_time;

        winbase.GetSystemTime(&system_time);
        winbase.SystemTimeToFileTime(&system_time, &file_time);

        ulong time = cast(ulong)file_time.dwLowDateTime;
        time += cast(ulong)file_time.dwHighDateTime << 32;

        tp.tv_sec = cast(long)((time - EPOCH) / 10_000_000L);
        tp.tv_usec = cast(long)(system_time.wMilliseconds * 1000);

        return 0;
    }
}

version (Posix) import core.sys.posix.sys.time : timeval, gettimeofday;

struct StopWatch {
@nogc nothrow:
private align(8):
    bool started;
    timeval timeStart, timeEnd;
    long timeMeasured;

public:
    this(bool autostart) {
        if (autostart)
            this.start();
    }

    void start() {
        this.started = true;
        gettimeofday(&this.timeStart, null), this.timeEnd = this.timeStart;
        this.timeMeasured = 0;
    }

    void stop() {
        if (this.started)
            this.elapsed(), this.started = false;
    }

    void restart() {
        this.stop(), this.start();
    }

    @property bool running() pure =>
        this.started;

    ulong elapsed() {
        if (this.started) {
            gettimeofday(&this.timeEnd, null),
            this.timeMeasured =
                (this.timeEnd.tv_sec - this.timeStart.tv_sec) * 1000_000 + (
                    this.timeEnd.tv_usec - this.timeStart.tv_usec);
        }
        return this.timeMeasured;
    }

    @property long elapsed(string op)()
            if (op == "usecs" || op == "msecs" || op == "seconds") {
        static if (op == "usecs")
            return this.elapsed();
        static if (op == "msecs")
            return this.elapsed() / 1000;
        static if (op == "seconds")
            return this.elapsed() / 1000_000;
    }
}

extern (C) void main() @nogc {
    auto sw = StopWatch(true);
    Bcaa!(int, int, Mallocator) aa0;
    scope (exit) {
        aa0.free;
        printf("Elapsed time: %lf, heap after aa0.free: %lu \n",
            cast(double)sw.elapsed!"usecs"() / 1000_000, Mallocator.instance.heap());
    }

    foreach (i; 0 .. 10_000_000)
        aa0[i] = i;
    printf("Heap of aa0[10_000_000] %lu\n", Mallocator.instance.heap());

    foreach (i; 2000 .. 1000_000)
        aa0.remove(i);
    printf("aa0[1000]: %d, heap: %lu\n", aa0[1000]);

    printf("Elapsed time: %lf, heap: %lu \n", cast(double)sw.elapsed!"usecs"() / 1000_000, Mallocator.instance.heap());

    {
        Bcaa!(string, string) aa1;
        scope (exit) {
            printf("Heap before aa1.free(): %lu\n", Mallocator.instance.heap());
            aa1.free;
            printf("After: %lu\n", Mallocator.instance.heap());
        }

        aa1["Stevie"] = "Ray Vaughan";
        aa1["Asım Can"] = "Gündüz";
        aa1["Dan"] = "Patlansky";
        aa1["İlter"] = "Kurcala";
        aa1["Кириллица"] = "Тоже работает";
        aa1.Ferhat = "Kurtulmuş";

        foreach (pair; aa1)
            printf("%s -> %s\n", (*pair.keyp).ptr, (*pair.valp).ptr);

        if (auto valptr = "Dan" in aa1)
            printf("Dan %s exists!\n", (*valptr).ptr);
        else
            printf("Dan does not exist!\n");

        assert(aa1.remove("Ferhat") == true);
        assert(aa1["Ferhat"] == null);
        assert(aa1.remove("Foe") == false);
        assert(aa1["İlter"] == "Kurcala");

        aa1.rehash();

        printf("%s\n", aa1["Stevie"].ptr);
        printf("%s\n", aa1["Asım Can"].ptr);
        printf("%s\n", aa1.Dan.ptr);
        printf("%s\n", aa1["Ferhat"].ptr);

        auto keys = aa1.keys;
        scope (exit)
            Mallocator.instance.dispose(keys);
        foreach (key; keys)
            printf("%s -> %s\n", key.ptr, aa1[key].ptr);

        struct Guitar {
            string brand;
        }

        Bcaa!(int, Guitar) guitars;
        scope (exit)
            guitars.free;

        guitars[0] = Guitar("Fender");
        guitars[3] = Guitar("Gibson");
        guitars[356] = Guitar("Stagg");

        assert(guitars[3].brand == "Gibson");

        printf("%s \n", guitars[356].brand.ptr);

        if (auto valPtr = 3 in guitars)
            printf("%s \n", (*valPtr).brand.ptr);
    }

    // Test "in" works for AA without allocated storage.
    {
        Bcaa!(int, int) emptyMap;
        assert(0 !in emptyMap);

    }

    // Try to force a memory leak - issue #5
    {
        struct S {
            int x;
            int y;
            string txt;
        }

        Bcaa!(int, S) aas;
        scope (exit) {
            printf("Heap before aas.free(): %lu\n", Mallocator.instance.heap());
            aas.free;
            printf("After: %lu\n", Mallocator.instance.heap());
        }

        for (int i = 1024; i < 2048; i++) {
            aas[i] = S(i, i * 2, "caca");
        }
        aas[100] = S(10, 20, "caca");

        printf("aas[100].x=%d aas[100].y=%d txt: %s\n", aas[100].x, aas[100].y, aas[100].txt.ptr);

        for (int i = 1024; i < 2048; i++)
            aas.remove(i);
    }
}
