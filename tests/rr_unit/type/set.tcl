start_server {
    tags {"set"}
    overrides {
        "set-max-intset-entries" 512
    }
} {
    proc create_set {key entries} {
        r del $key
        foreach entry $entries { r sadd $key $entry }
    }

    test {SADD, SCARD, SISMEMBER, SMEMBERS basics - regular set} {
        create_set myset {foo}
        assert_equal 1 [r sadd myset bar]
        assert_equal 0 [r sadd myset bar]
        assert_equal 2 [r scard myset]
        assert_equal 1 [r sismember myset foo]
        assert_equal 1 [r sismember myset bar]
        assert_equal 0 [r sismember myset bla]
        assert_equal {bar foo} [lsort [r smembers myset]]
    }

    test {SADD, SCARD, SISMEMBER, SMEMBERS basics - hashtable} {
        create_set myset {17}
        assert_equal 1 [r sadd myset 16]
        assert_equal 0 [r sadd myset 16]
        assert_equal 2 [r scard myset]
        assert_equal 1 [r sismember myset 16]
        assert_equal 1 [r sismember myset 17]
        assert_equal 0 [r sismember myset 18]
        assert_equal {16 17} [lsort [r smembers myset]]
    }

    test "SADD a non-integer against an hashtable" {
        create_set myset {1 2 3}
        assert_equal 1 [r sadd myset a]
        assert_equal {1 2 3 a} [lsort [r smembers myset]]
    }

    test "SADD an integer larger than 64 bits" {
        r del myset
        create_set myset {213244124402402314402033402}
        assert_equal 1 [r sismember myset 213244124402402314402033402]
    }

    test "SADD overflows the maximum allowed integers in an hashtable" {
        r del myset
        for {set i 0} {$i < 512} {incr i} { r sadd myset $i }
        assert_equal 1 [r sadd myset 512]
    }

    test {Variadic SADD} {
        r del myset
        assert_equal 3 [r sadd myset a b c]
        assert_equal 2 [r sadd myset A a b c B]
        assert_equal [lsort {A B a b c}] [lsort [r smembers myset]]
    }

    test "Set encoding after DEBUG RELOAD" {
        r del myhashtable myhashset mylargehashtable
        for {set i 0} {$i <  100} {incr i} { r sadd myhashtable $i }
        for {set i 0} {$i < 1280} {incr i} { r sadd mylargehashtable $i }
        for {set i 0} {$i <  256} {incr i} { r sadd myhashset [format "i%03d" $i] }

        r debug reload

        for {set i 0} {$i < 100} {incr i} { 
          assert_equal 1 [r sismember myhashtable $i]
        }

        for {set i 0} {$i < 1280} {incr i} {
          assert_equal 1 [r sismember mylargehashtable $i]
        }

        for {set i 0} {$i < 256} {incr i} {
          assert_equal 1 [r sismember myhashset [format "i%03d" $i]]
        }
    }

    test {SREM basics - regular set} {
        create_set myset {foo bar ciao}
        assert_equal 0 [r srem myset qux]
        assert_equal 1 [r srem myset foo]
        assert_equal {bar ciao} [lsort [r smembers myset]]
    }

    test {SREM basics - hashtable} {
        create_set myset {3 4 5}
        assert_equal 0 [r srem myset 6]
        assert_equal 1 [r srem myset 4]
        assert_equal {3 5} [lsort [r smembers myset]]
    }

    test {SREM with multiple arguments} {
        r del myset
        r sadd myset a b c d
        assert_equal 0 [r srem myset k k k]
        assert_equal 2 [r srem myset b d x y]
        lsort [r smembers myset]
    } {a c}

    test {SREM variadic version with more args needed to destroy the key} {
        r del myset
        r sadd myset 1 2 3
        r srem myset 1 2 3 4 5 6 7 8
    } {3}

    foreach {type} {hashtable hashtable} {
        for {set i 1} {$i <= 5} {incr i} {
            r del [format "set%d" $i]
        }
        for {set i 0} {$i < 200} {incr i} {
            r sadd set1 $i
            r sadd set2 [expr $i+195]
        }
        foreach i {199 195 1000 2000} {
            r sadd set3 $i
        }
        for {set i 5} {$i < 200} {incr i} {
            r sadd set4 $i
        }
        r sadd set5 0

        # To make sure the sets are encoded as the type we are testing -- also
        # when the VM is enabled and the values may be swapped in and out
        # while the tests are running -- an extra element is added to every
        # set that determines its encoding.
        set large 200
        if {$type eq "hashtable"} {
            set large foo
        }

        for {set i 1} {$i <= 5} {incr i} {
            r sadd [format "set%d" $i] $large
        }
    }

    foreach {type contents} {hashtable {a b c} hashtable {1 2 3}} {
        test "SPOP basics - $type" {
            create_set myset $contents
            assert_equal $contents [lsort [list [r spop myset] [r spop myset] [r spop myset]]]
            assert_equal 0 [r scard myset]
        }

        test "SRANDMEMBER - $type" {
            create_set myset $contents
            unset -nocomplain myset
            array set myset {}
            for {set i 0} {$i < 100} {incr i} {
                set myset([r srandmember myset]) 1
            }
            assert_equal $contents [lsort [array names myset]]
        }
    }

    test "SRANDMEMBER with <count> against non existing key" {
        r srandmember nonexisting_key 100
    } {}

    foreach {type contents} {
        hashtable {
            1 5 10 50 125 50000 33959417 4775547 65434162
            12098459 427716 483706 2726473884 72615637475
            MARY PATRICIA LINDA BARBARA ELIZABETH JENNIFER MARIA
            SUSAN MARGARET DOROTHY LISA NANCY KAREN BETTY HELEN
            SANDRA DONNA CAROL RUTH SHARON MICHELLE LAURA SARAH
            KIMBERLY DEBORAH JESSICA SHIRLEY CYNTHIA ANGELA MELISSA
            BRENDA AMY ANNA REBECCA VIRGINIA KATHLEEN
        }
        hashtable {
            0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
            20 21 22 23 24 25 26 27 28 29
            30 31 32 33 34 35 36 37 38 39
            40 41 42 43 44 45 46 47 48 49
        }
    } {
        test "SRANDMEMBER with <count> - $type" {
            create_set myset $contents
            unset -nocomplain myset
            array set myset {}
            foreach ele [r smembers myset] {
                set myset($ele) 1
            }
            assert_equal [lsort $contents] [lsort [array names myset]]

            # Make sure that a count of 0 is handled correctly.
            assert_equal [r srandmember myset 0] {}

            # We'll stress different parts of the code, see the implementation
            # of SRANDMEMBER for more information, but basically there are
            # four different code paths.
            #
            # PATH 1: Use negative count.
            #
            # 1) Check that it returns repeated elements.
            set res [r srandmember myset -100]
            assert_equal [llength $res] 100

            # 2) Check that all the elements actually belong to the
            # original set.
            foreach ele $res {
                assert {[info exists myset($ele)]}
            }

            # 3) Check that eventually all the elements are returned.
            unset -nocomplain auxset
            set iterations 1000
            while {$iterations != 0} {
                incr iterations -1
                set res [r srandmember myset -10]
                foreach ele $res {
                    set auxset($ele) 1
                }
                if {[lsort [array names myset]] eq
                    [lsort [array names auxset]]} {
                    break;
                }
            }
            assert {$iterations != 0}

            # PATH 2: positive count (unique behavior) with requested size
            # equal or greater than set size.
            foreach size {50 100} {
                set res [r srandmember myset $size]
                assert_equal [llength $res] 50
                assert_equal [lsort $res] [lsort [array names myset]]
            }

            # PATH 3: Ask almost as elements as there are in the set.
            # In this case the implementation will duplicate the original
            # set and will remove random elements up to the requested size.
            #
            # PATH 4: Ask a number of elements definitely smaller than
            # the set size.
            #
            # We can test both the code paths just changing the size but
            # using the same code.

            foreach size {45 5} {
                set res [r srandmember myset $size]
                assert_equal [llength $res] $size

                # 1) Check that all the elements actually belong to the
                # original set.
                foreach ele $res {
                    assert {[info exists myset($ele)]}
                }

                # 2) Check that eventually all the elements are returned.
                unset -nocomplain auxset
                set iterations 1000
                while {$iterations != 0} {
                    incr iterations -1
                    set res [r srandmember myset -10]
                    foreach ele $res {
                        set auxset($ele) 1
                    }
                    if {[lsort [array names myset]] eq
                        [lsort [array names auxset]]} {
                        break;
                    }
                }
                assert {$iterations != 0}
            }
        }
    }

    proc setup_move {} {
        r del myset3 myset4
        create_set myset1 {1 a b}
        create_set myset2 {2 3 4}
    }

    test "SMOVE basics - from regular set to hashtable" {
        # move a non-integer element to an hashtable should convert encoding
        setup_move
        assert_equal 1 [r smove myset1 myset2 a]
        assert_equal {1 b} [lsort [r smembers myset1]]
        assert_equal {2 3 4 a} [lsort [r smembers myset2]]

        # move an integer element should not convert the encoding
        setup_move
        assert_equal 1 [r smove myset1 myset2 1]
        assert_equal {a b} [lsort [r smembers myset1]]
        assert_equal {1 2 3 4} [lsort [r smembers myset2]]
    }

    test "SMOVE basics - from hashtable to regular set" {
        setup_move
        assert_equal 1 [r smove myset2 myset1 2]
        assert_equal {1 2 a b} [lsort [r smembers myset1]]
        assert_equal {3 4} [lsort [r smembers myset2]]
    }

    test "SMOVE non existing key" {
        setup_move
        assert_equal 0 [r smove myset1 myset2 foo]
        assert_equal {1 a b} [lsort [r smembers myset1]]
        assert_equal {2 3 4} [lsort [r smembers myset2]]
    }

    test "SMOVE non existing src set" {
        setup_move
        assert_equal 0 [r smove noset myset2 foo]
        assert_equal {2 3 4} [lsort [r smembers myset2]]
    }

    test "SMOVE from regular set to non existing destination set" {
        setup_move
        assert_equal 1 [r smove myset1 myset3 a]
        assert_equal {1 b} [lsort [r smembers myset1]]
        assert_equal {a} [lsort [r smembers myset3]]
    }

    test "SMOVE from hashtable to non existing destination set" {
        setup_move
        assert_equal 1 [r smove myset2 myset3 2]
        assert_equal {3 4} [lsort [r smembers myset2]]
        assert_equal {2} [lsort [r smembers myset3]]
    }

    test "SMOVE wrong src key type" {
        setup_move
        r set x 10
        assert_equal 0 [r smove x myset2 2]
    }

    test "SMOVE wrong dst key type" {
        setup_move
        r set x 10
        assert_equal 1 [r smove myset2 x 2]
    }

    test "SMOVE with identical source and destination" {
        r del set
        r sadd set a b c
        r smove set set b
        lsort [r smembers set]
    } {a b c}

    test "SMOVE a member exists in destination set" {
        r del set1 set2
        r sadd set1 a b c d
	      r sadd set2 a b c d e
        r smove set1 set2 a
        assert_equal {b c d} [lsort [r smembers set1]]
        assert_equal {a b c d e} [lsort [r smembers set2]]
	      assert_equal 3 [r scard set1]
	      assert_equal 5 [r scard set2]
    }

    tags {slow} {
        test {hashtables implementation stress testing} {
            for {set j 0} {$j < 20} {incr j} {
                unset -nocomplain s
                array set s {}
                r del s
                set len [randomInt 1024]
                for {set i 0} {$i < $len} {incr i} {
                    randpath {
                        set data [randomInt 65536]
                    } {
                        set data [randomInt 4294967296]
                    } {
                        set data [randomInt 18446744073709551616]
                    }
                    set s($data) {}
                    r sadd s $data
                }

                assert_equal [lsort [r smembers s]] [lsort [array names s]]
                set len [array size s]
                for {set i 0} {$i < $len} {incr i} {
                    set e [r spop s]
                    if {![info exists s($e)]} {
                        puts "Can't find '$e' on local array"
                        puts "Local array: [lsort [r smembers s]]"
                        puts "Remote array: [lsort [array names s]]"
                        error "exception"
                    }
                    array unset s $e
                }
                assert_equal [r scard s] 0
                assert_equal [array size s] 0
            }
        }
    }
}