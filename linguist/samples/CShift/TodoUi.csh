// demo-ui: the widgets of System.Ui in a small to-do list. The state of the program is the struct App; Draw describes
// the window for it, every frame, and changes it where the user did something.

using System;
using System.Ui;

struct Task
{
    string Title;
    bool Done;
}

struct App
{
    List<Task> Tasks;
    string NewTitle;
    int Selected;
    int Filter;          // 0 all, 1 open, 2 done
    bool Dark;
    double Zoom;         // the scale of the ui, relative to the screen's
}

void Draw(Ui ui, ref App app)
{
    int done = 0;
    foreach (var task in app.Tasks)
    {
        if (task.Done)
            done += 1;
    }

    using (ui.Row())
    {
        ui.Label("To do");
        ui.Note($"{done} of {app.Tasks.Count()} done");
    }
    ui.ProgressBar(app.Tasks.Count() > 0 ? (double)done / (double)app.Tasks.Count() : 0.0);

    // a new task: Enter in the text box or the button
    using (ui.Row())
    {
        ui.TextBox("new", ref app.NewTitle);
        bool add = ui.Button("Add") || ui.Submitted("new");
        if (add && app.NewTitle.Trim().Length > 0)
        {
            app.Tasks.Add(Task { Title = app.NewTitle.Trim().ToString() });
            app.NewTitle = "";
            ui.SetFocus("new");
        }
    }

    using (ui.Row())
    {
        ui.Radio("All", ref app.Filter, 0);
        ui.Radio("Open", ref app.Filter, 1);
        ui.Radio("Done", ref app.Filter, 2);
    }

    using (ui.Scroll("tasks", 180))
    {
        for (var i = 0; i < app.Tasks.Count(); i += 1)
        {
            var task = app.Tasks[i];
            if ((app.Filter == 1 && task.Done) || (app.Filter == 2 && !task.Done))
                continue;
            using (ui.Id(i))
            {
                using (ui.Row())
                {
                    if (ui.Checkbox("##done", ref task.Done))
                        app.Tasks[i] = task;
                    if (ui.ListItem(task.Title, app.Selected == i))
                        app.Selected = i;
                }
            }
        }
    }

    using (ui.Row())
    {
        bool hasSelection = app.Selected >= 0 && app.Selected < app.Tasks.Count();
        if (ui.Button("Remove selected") && hasSelection)
        {
            app.Tasks.RemoveAt(app.Selected);
            app.Selected = -1;
        }
        if (ui.Button("Remove done"))
        {
            app.Tasks = app.Tasks.Where(t => !t.Done);
            app.Selected = -1;
        }
    }

    using (ui.Panel("Settings"))
    {
        if (ui.Checkbox("Dark theme", ref app.Dark))
            ui.SetTheme(app.Dark ? Theme.Dark() : Theme.Light());
        using (ui.Columns(2))
        {
            ui.Label($"Zoom {app.Zoom * 100.0:F0} %");
            ui.Slider("zoom", ref app.Zoom, 0.75, 2.0);
        }
        ui.Text("Tab moves between the controls, Enter and Space press buttons, the arrow keys move sliders. " +
                "Ctrl+C, Ctrl+X and Ctrl+V work in text boxes.");
    }
}

int Main(string[] args)
{
    // --frames N: draw N frames and close (for screenshots and tests)
    int frames = 0;
    if (args.Length == 2 && args[0] == "--frames" && args[1].ParseInt() is int n)
        frames = n;

    var window = try Window.Open("CShift - System.Ui", 420, 560);
    var ui = Ui.Create();
    var app = App { Tasks = List<Task>.Create(), NewTitle = "", Selected = -1, Zoom = 1.0 };
    app.Tasks.Add(Task { Title = "Write the window layer", Done = true });
    app.Tasks.Add(Task { Title = "Draw text with a bitmap font", Done = true });
    app.Tasks.Add(Task { Title = "Lay out rows, columns and panels" });
    app.Tasks.Add(Task { Title = "Scroll long lists" });
    app.Tasks.Add(Task { Title = "Try it on Linux" });

    int count = 0;
    while (window.Update())
    {
        ui.Begin(window.Input(), window.Width(), window.Height(), window.Scale() * app.Zoom);
        Draw(ui, ref app);
        if (frames > 0)
            window.Show(ui.End()); // as an image: the next Update does not wait for input
        else
            window.Show(ui);
        count += 1;
        if (frames > 0 && count >= frames)
            break;
    }
    window.Dispose();
    return 0;
}
