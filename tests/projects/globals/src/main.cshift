using App.Config;

int Runs;
string Banner = "runs of " + Name;

int Main()
{
    Runs += 1;
    Add("start");
    App.Config.Version += 1;
    Add("version " + Version.ToString() + " next " + Next.ToString());
    Console.WriteLine(Banner + ": " + Runs.ToString());
    foreach (var line in Log)
        Console.WriteLine(line);
    return 0;
}
