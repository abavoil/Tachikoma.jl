using Test
using Tachikoma

const T = Tachikoma

# ── PTY child reaping ────────────────────────────────────────────────────────
# Regression: pty_alive returned early on !alive, so once the reader task
# observed EOF (or a read error) and set alive=false, no code path ever
# called waitpid again — the exited child lingered as a zombie until the
# parent process exited. On the Kaimon headless server that meant a server
# restart to clear the <defunct> children.
#
# Not supported on Windows (no POSIX pty there; the ConPTY path has no child
# to wait on).

if !Sys.iswindows()
    function _process_state(pid::Cint)
        out = try
            read(`ps -o stat= -p $pid`, String)
        catch
            ""
        end
        return strip(out)
    end

    @testset "pty_alive reaps after the reader observed EOF" begin
        pty = T.pty_spawn(["true"])   # exits immediately
        deadline = time() + 5
        while pty.alive && time() < deadline
            sleep(0.02)
        end
        @test !pty.alive              # reader saw the exit and flagged it

        # THE regression: pty_alive must REAP, not just report. Before the
        # fix the child stayed in the process table as a zombie ('Z').
        @test T.pty_alive(pty) == false
        @test !occursin("Z", _process_state(pty.child_pid))

        # Reaping is one-shot: a second call neither crashes nor misreports.
        @test T.pty_alive(pty) == false
        T.pty_close!(pty)
    end

    @testset "pty_alive keeps reporting a live child" begin
        pty = T.pty_spawn(["sleep", "5"])
        try
            @test T.pty_alive(pty) == true
        finally
            T.pty_close!(pty)
        end
    end
end
