using System;
using System.Drawing;
using System.Windows.Forms;

namespace WowVisionInstaller
{
    /// <summary>
    /// "What should be installed alongside WowVision?" — the installer's own
    /// language and the optional components.
    ///
    /// The important part is not the layout, it is the accessible names. Each
    /// control announces its label AND what it does, and the visible description
    /// says the same thing. (The Sku installer once had an explanation on screen
    /// that the checkbox's accessible name withheld — from exactly the users who
    /// could not see it.)
    ///
    /// Shorter than the Sku page it comes from: WowVision has no voice packs to
    /// choose (its sounds are inside the one release zip), no companion or
    /// third-party addons, and no login tool.
    /// </summary>
    public class ComponentsForm : WizardForm
    {
        private Label _installerLangLabel;
        private ComboBox _installerLangCombo;
        private CheckBox _forceCheck, _shortcutCheck, _sapi2srCheck, _windowsVoicesCheck;
        private Label _forceDesc, _shortcutDesc, _sapi2srDesc, _windowsVoicesDesc;

        // Combo order == this array, so adding a language is a one-line change
        // and no index literal anywhere has to be kept in step. Each entry is
        // named in its OWN language: someone looking for French is looking for
        // "Français", not for whatever the current UI language calls it.
        private static readonly Lang[] _langOrder = { Lang.En, Lang.De, Lang.Fr };

        private static string LangDisplayName(Lang l)
        {
            if (l == Lang.De) return "Deutsch";
            if (l == Lang.Fr) return "Français";
            return "English";
        }

        /// <summary>The chosen options. Valid once Result is Next.</summary>
        public InstallOptions Options { get; private set; } = new InstallOptions();

        public ComponentsForm(InstallOptions initial)
        {
            Options = initial ?? new InstallOptions();
            BuildContent();
            ApplyTexts();
        }

        private void BuildContent()
        {
            int y = ContentTop;

            _installerLangLabel = AddContentLabel(ContentLeft, y, ContentWidth, 18);
            y += 20;
            _installerLangCombo = new ComboBox
            {
                Location = new Point(ContentLeft, y),
                Size = new Size(240, 24),
                DropDownStyle = ComboBoxStyle.DropDownList,
            };
            foreach (var l in _langOrder)
                _installerLangCombo.Items.Add(LangDisplayName(l));
            _installerLangCombo.SelectedIndex = Math.Max(0, Array.IndexOf(_langOrder, Loc.Current));
            _installerLangCombo.SelectedIndexChanged += OnInstallerLanguageChanged;
            Controls.Add(_installerLangCombo);
            y += 40;

            AddOption(ref _shortcutCheck, ref _shortcutDesc, ref y, Options.DesktopShortcut);
            AddOption(ref _sapi2srCheck, ref _sapi2srDesc, ref y, Options.InstallSapi2Sr);
            AddOption(ref _windowsVoicesCheck, ref _windowsVoicesDesc, ref y, Options.InstallWindowsVoices);
            AddOption(ref _forceCheck, ref _forceDesc, ref y, Options.Force);

            SetContentHeight(y);
            ActiveControl = _shortcutCheck;
        }

        /// <summary>Adds a checkbox plus its own description label underneath.</summary>
        private void AddOption(ref CheckBox check, ref Label desc, ref int y, bool initial)
        {
            check = new CheckBox
            {
                Location = new Point(ContentLeft, y),
                Size = new Size(ContentWidth, 22),
                Font = new Font(Font.FontFamily, 9.5f, FontStyle.Bold),
                Checked = initial,
            };
            Controls.Add(check);
            y += 22;

            desc = AddContentLabel(ContentLeft + 22, y, ContentWidth - 22, 32);
            y += 40;
        }

        private void OnInstallerLanguageChanged(object sender, EventArgs e)
        {
            int i = _installerLangCombo.SelectedIndex;
            Loc.Set(i >= 0 && i < _langOrder.Length ? _langOrder[i] : Lang.En);
            ApplyTexts();
        }

        private void ApplyTexts()
        {
            Text = Loc.Get("app.title") + " " + InstallerVersion();
            HeadingLabel.Text = Loc.Get("components.heading");
            BodyLabel.Text = Loc.Get("components.body");
            BackButton.Text = Loc.Get("nav.back");
            NextButton.Text = Loc.Get("nav.install");

            _installerLangLabel.Text = Loc.Get("ui.installerLanguage");
            _installerLangCombo.AccessibleName = Loc.Get("acc.installerLanguage");

            SetOptionText(_shortcutCheck, _shortcutDesc, "shortcut");
            SetOptionText(_sapi2srCheck, _sapi2srDesc, "sapi2sr");
            SetOptionText(_windowsVoicesCheck, _windowsVoicesDesc, "windowsVoices");
            SetOptionText(_forceCheck, _forceDesc, "force");

            AnnouncePage();
        }

        /// <summary>
        /// Applies an option's label and description, and composes the two into
        /// the accessible name so focusing the checkbox explains it.
        /// </summary>
        private static void SetOptionText(CheckBox check, Label desc, string key)
        {
            check.Text = Loc.Get("opt." + key + ".label");
            desc.Text = Loc.Get("opt." + key + ".desc");
            check.AccessibleName = $"{check.Text}. {desc.Text}";
        }

        protected override void OnNext()
        {
            Options = new InstallOptions
            {
                DesktopShortcut = _shortcutCheck.Checked,
                InstallSapi2Sr = _sapi2srCheck.Checked,
                InstallWindowsVoices = _windowsVoicesCheck.Checked,
                Force = _forceCheck.Checked,
            };
            Result = WizardResult.Next;
            Close();
        }
    }
}
