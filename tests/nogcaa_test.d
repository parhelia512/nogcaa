module nogcaa_test;

import nogcaa;
import nogcsw;
import core.stdc.stdio;

extern (C) void main() @nogc {
    {
        printf("Mallocator test\n");
        auto memory = Mallocator.allocate!int(1024);
        scope (exit) {
            Mallocator.instance.deallocate(memory);
            printf("Heap after deallocation: %lu\n", Mallocator.instance.heap());
        }

        printf("Heap after allocation: %lu\n", Mallocator.instance.heap());
        printf("[Array] length: %lu\n", memory.length);
        printf("Pointer length: %lu\n", Mallocator.length(memory.ptr));
        printf("Pointer sizeof: %lu\n", Mallocator.__sizeof(memory.ptr));

        assert(memory.length == Mallocator.length(memory.ptr));
    }

    auto sw = StopWatch(true);
    Nogcaa!(int, int, Mallocator) aa0;
    scope (exit) {
        aa0.free;
        printf("Elapsed time: %lf, heap after aa0.free: %lu \n",
            cast(double)sw.elapsed!"usecs"() / 1_000_000, Mallocator.instance.heap());
        assert(Mallocator.instance.heap() == 0);
    }

    foreach (i; 0 .. 1_000_000)
        aa0[i] = i;
    printf("Heap of aa0[%lu]: %lu\n", aa0.length, Mallocator.instance.heap());

    foreach (i; 2_000 .. 1_000_000)
        aa0.remove(i);
    printf("aa0[1_000]: %d\n", aa0[1_000]);

    printf("Elapsed time: %lf, heap: %lu \n", cast(double)sw.elapsed!"usecs"() / 1_000_000, Mallocator.instance.heap());

    {
        Nogcaa!(string, string) aa1;
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

        Nogcaa!(int, Guitar) guitars;
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

    {
        Nogcaa!(int, int) emptyMap;
        assert(0 !in emptyMap);

    }

    {
        struct S {
            int x;
            int y;
            string txt;
        }

        Nogcaa!(int, S) aas;
        scope (exit) {
            printf("Heap before aas.free(): %lu\n", Mallocator.instance.heap());
            aas.free;
            printf("After: %lu\n", Mallocator.instance.heap());
        }

        for (size_t j = 0; j < 100; j++) {
            for (int i = 0; i < 100_000; i++)
                aas[i] = S(i, i * 2, "caca");

            aas[100] = S(10, 20, "caca");

            for (int i = 1_000; i < 90_000; i++)
                aas.remove(i);
        }
    }
}
