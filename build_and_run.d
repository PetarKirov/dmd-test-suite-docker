import std.algorithm : joiner, startsWith;
import std.conv : to;
import std.exception : enforce;
import std.file : getcwd;
import std.format : format;
import std.getopt : arraySep, assignChar, getopt;
import std.parallelism : totalCPUs;
import std.process : environment, executeShell, spawnShell, wait;
import std.stdio : writeln, writefln;
import std.string : isNumeric;
import std.typecons : tuple;

enum Model { none, m32 = 32, m64 = 64 }
immutable knownRepos = ["dmd", "druntime", "phobos"];
immutable knownBranches = ["master", "stable"];

alias allowedRepos = () => knownRepos.dup.joiner("|").to!string;
alias allowedBranch = () => knownBranches.dup.joiner("|").to!string;

void main(string[] args)
{
    Model model;
    string[string] repoBranchMap;

    arraySep = ",";
    assignChar = ':';
    auto cmdOpts = getopt(args,
        "repos", &repoBranchMap,
        "model", &model);

    enum bits = size_t.sizeof * 8;
    const arch = model == model.none? cast(Model)bits : model;
    const cpus = getTotalSystemMemory() > int.max ? totalCPUs : 1;
    const dmdPath = "~/dlang/dmd-%s/linux/bin%s/dmd"
        .format(environment["DMD_STABLE_VERSION"], bits);

    if (cmdOpts.helpWanted)
    {
        writefln(
"Usage: docker run -it dmd-test-suite-docker " ~
"[--repos:{%1$s}:{%2$s|pr/<number>}[,{%1$s}:{%2$s|pr/<number>}]...]

Using dmd binary from: '%3$s'.

Examples:
       docker run -it dmd-test-suite-docker
       docker run -it dmd-test-suite-docker --model:m32
       docker run -it dmd-test-suite-docker --repos:dmd:stable --model:m64
       docker run -it dmd-test-suite-docker --repos:dmd:pr/6000
       docker run -it dmd-test-suite-docker " ~
"--repos:dmd:pr/6000,druntime:stable,phobos:stable",
        allowedRepos(), allowedBranch(), dmdPath);
        return;
    }

    [
        repoBranchMap.gitCloneCommands("dmd", "master"),
        repoBranchMap.gitCloneCommands("druntime", "master"),
        repoBranchMap.gitCloneCommands("phobos", "master"),
    ].executeAll();

    [
        "make -C dmd -f posix.mak -j%s MODEL=%d HOST_DMD=%s".format(cpus, arch, dmdPath),
        "make -C druntime -f posix.mak -j%s MODEL=%d".format(cpus, arch),
        "make -C phobos -f posix.mak -j%s MODEL=%d".format(cpus, arch)
    ].executeAll();

    [
        "make -C dmd/test -j%s MODEL=%d".format(cpus, arch)
    ].executeAll();
}

ulong getTotalSystemMemory()
{
    import core.sys.posix.unistd;
    ulong pages = sysconf(_SC_AVPHYS_PAGES);
    ulong pageSize = sysconf(_SC_PAGE_SIZE);
    return pages * pageSize;
}

string[] gitCloneCommands(string[string] repoBranchSpecs,
        string repo, string defaultBranchSpec)
{
    auto spec = repo in repoBranchSpecs;
    auto branchSpec = spec? *spec : defaultBranchSpec;

    enforce(repo.among!knownRepos,
        "Expected `%s` to be one of: `%s`".format(repo, knownRepos));

    enforce(branchSpec.among!knownBranches ||
        (branchSpec.startsWith("pr/") && branchSpec[3 .. $].isNumeric),
        "Expected `%s|pr/<number>`, but got `%s`".
            format(allowedBranch(), branchSpec));

    if (branchSpec.among!knownBranches)
        return [ "git clone -b %s --depth=1 https://github.com/dlang/%s"
                .format(branchSpec, repo) ];

    uint pr = branchSpec[3..$].to!uint;

    return
    [
        "git init %s".format(repo),
        "git -C %1$s remote add origin https://github.com/dlang/%1$s".format(repo),
        "git -C %s fetch --depth=1 origin pull/%2$s/head:pr/%2$s".format(repo, pr),
        "git -C %s checkout pr/%s".format(repo, pr)
    ];
}

auto among(alias values, T)(T val)
{
    import std.algorithm.comparison : among_ = among;
    import std.meta : aliasSeqOf;
    return val.among_(aliasSeqOf!values);
}

void executeAll(R)(R commands)
{
    import std.range : ElementType;

    static if (is(ElementType!R == string)) auto cmds = commands;
    else auto cmds = commands.joiner;

    foreach (cmd; cmds)
    {
        writefln("== executing: `%s` in `%s`... ==", cmd, getcwd());
        (spawnShell(cmd).wait == 0).enforce("`" ~ cmd ~ "` failed.");
        writefln("== `%s` finished successfully. ==\n\n", cmd);
    }
}
