package com.kaireborn.audit;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * KaiReborn — full-feature companion, the honest descendant of XKatrina.
 *
 * Every screen maps 1:1 to something the legacy app did, but each action goes
 * through the module CLI (`kai`), which:
 *   - defaults to dry-run,
 *   - requires module mode "full" before writing,
 *   - logs every path it touches,
 *   - refuses critical packages.
 *
 * Intentionally absent, with the audit reason (docs/EVIDENCE.md):
 *   - global cache / empty-dir purge   : 1643 dirs deleted on the audit device
 *   - /data/system/users/0 file wipe   : 19 settings & package files
 *   - remount / or /vendor read-write  : dm-* devices, both read-only
 *   - openrecoveryscript + reboot      : A/B device, no recovery partition
 *   - Advertising ID write             : lives in GMS, not writable by an app
 *   - IMEI / serial spoofing           : not readable by an app since Android 10
 *
 * The app has no network permission, so no identifier can leave the device.
 */
public class MainActivity extends Activity {

    private static final String MOD = "/data/adb/modules/kaireborn";

    private TextView status;
    private TextView output;
    private EditText pkg;
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(10);
        root.setPadding(pad, pad, pad, pad);

        status = new TextView(this);
        status.setTextSize(12);
        status.setText("checking…");

        output = new TextView(this);
        output.setTextSize(11);
        output.setTextIsSelectable(true);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(output);

        // ---- read-only -----------------------------------------------------
        root.addView(section("Read-only"));
        root.addView(btn("Audit build properties", "kai audit"));
        root.addView(btn("Show identifiers", null));
        root.addView(btn("Write audit snapshot to log", "kai audit"));

        // ---- identity profile ----------------------------------------------
        root.addView(section("Identity profile"));
        root.addView(btn("List profiles", "kai profile list"));
        root.addView(btn("Create profile from this device", "kai profile create device"));
        root.addView(btn("Apply profile · dry run", "kai profile apply device"));
        root.addView(btn("Apply profile · REAL", "kai mode full; kai profile apply device --apply"));

        // ---- wipe / reset ---------------------------------------------------
        root.addView(section("Wipe & reset (dry run first)"));
        root.addView(btn("Wipe Google data", "kai wipegms"));
        root.addView(btn("Wipe Google data + GMS", "kai wipegms --with-gms"));
        root.addView(btn("Reset Android ID", "kai ssaid"));
        root.addView(btn("Reset Android ID · REAL", "kai mode full; kai ssaid --apply"));
        root.addView(btn("Clear IFW rules", "kai ifw"));
        root.addView(btn("Recompile ART", "kai dalvik"));

        // ---- per app --------------------------------------------------------
        root.addView(section("Per app"));
        pkg = new EditText(this);
        pkg.setHint("package, e.g. com.example.app");
        pkg.setTextSize(13);
        root.addView(pkg);
        root.addView(btn("Clear app data", null));
        root.addView(btn("Reinstall via Play Store slot", null));
        root.addView(btn("Clear app cache", null));

        // ---- module ---------------------------------------------------------
        root.addView(section("Module control"));
        root.addView(btn("Mode: safe", "kai mode safe"));
        root.addView(btn("Mode: full — enables writes", "kai mode full"));
        root.addView(btn("Mode: audit — observe only", "kai mode audit"));
        root.addView(btn("Open system Ad-ID settings", null));

        root.addView(status);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);

        refreshStatus();
    }

    // --- view helpers -------------------------------------------------------

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    private TextView section(String t) {
        TextView v = new TextView(this);
        v.setText(t.toUpperCase());
        v.setTextSize(11);
        v.setPadding(0, dp(12), 0, dp(2));
        return v;
    }

    private Button btn(String label, final String cmd) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(13);
        b.setTag(cmd == null ? "" : cmd);
        b.setOnClickListener(click);
        return b;
    }

    private final View.OnClickListener click = new View.OnClickListener() {
        public void onClick(View v) {
            String cmd = String.valueOf(v.getTag());
            if (cmd == null || cmd.isEmpty() || "null".equals(cmd)) {
                handleSpecial(v);
            } else {
                run(cmd);
            }
        }
    };

    private void handleSpecial(View v) {
        Button b = (Button) v;
        String label = String.valueOf(b.getText());
        if (label.startsWith("Show identifiers")) {
            showIdentifiers();
        } else if (label.startsWith("Clear app data")) {
            run("kai pkgreset " + pkgText());
        } else if (label.startsWith("Reinstall")) {
            run("kai pkgreinstall " + pkgText());
        } else if (label.startsWith("Clear app cache")) {
            run("kai cleaner " + pkgText());
        } else if (label.startsWith("Open system Ad-ID")) {
            try {
                startActivity(new Intent(Settings.ACTION_PRIVACY_SETTINGS));
            } catch (Exception e) {
                append("cannot open settings: " + e.getMessage());
            }
        }
    }

    private String pkgText() {
        return pkg.getText().toString().trim();
    }

    // --- root plumbing ------------------------------------------------------

    private String sh(String cmd) {
        StringBuilder sb = new StringBuilder();
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start();
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) sb.append(line).append('\n');
            p.waitFor();
        } catch (Exception e) {
            sb.append("exec error: ").append(e.getMessage());
        } finally {
            if (p != null) try { p.destroy(); } catch (Exception ignored) {}
        }
        return sb.toString();
    }

    private void append(String s) {
        output.append(s + "\n");
    }

    private void run(final String cmd) {
        output.setText("");
        append("$ kai " + cmd.replaceFirst("^kai\\s+", ""));
        new Thread(new Runnable() {
            public void run() {
                String c = cmd.replaceFirst("^kai\\s+", "");
                final String out = sh("sh " + MOD + "/kai " + c + " 2>&1");
                ui.post(new Runnable() {
                    public void run() {
                        append(out.isEmpty() ? "(no output)" : out);
                        refreshStatus();
                    }
                });
            }
        }).start();
    }

    /** Read-only identifier report. Never edits anything. */
    private void showIdentifiers() {
        output.setText("");
        append("── identifiers (read-only) ──");
        new Thread(new Runnable() {
            public void run() {
                StringBuilder sb = new StringBuilder();
                String adid = sh("cat /data/user/0/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null");
                sb.append("Advertising ID (owned by Play Services, not writable):\n");
                if (adid.trim().isEmpty()) {
                    sb.append("  no GAID yet\n");
                } else {
                    for (String l : adid.split("\n")) {
                        String t = l.trim();
                        if (t.startsWith("<string") || t.startsWith("<boolean") || t.startsWith("<long"))
                            sb.append("  ").append(t).append('\n');
                    }
                }
                sb.append("\nAndroid ID (per-app, regenerable only):\n");
                sb.append("  store: ").append(sh("ls -l /data/system/users/0/settings_ssaid.xml 2>/dev/null").trim()).append('\n');
                sb.append("  apps:  ").append(sh("grep -c 'com\\.' /data/system/users/0/settings_ssaid.xml 2>/dev/null").trim()).append('\n');

                sb.append("\nBuild identity:\n");
                String[] props = {"ro.product.manufacturer", "ro.product.model", "ro.product.brand",
                        "ro.product.device", "ro.build.fingerprint", "ro.build.version.release",
                        "ro.build.version.sdk", "ro.build.tags", "ro.build.type"};
                for (String p : props) {
                    sb.append("  ").append(p).append(" = ").append(sh("getprop " + p).trim()).append('\n');
                }
                final String s = sb.toString();
                ui.post(new Runnable() {
                    public void run() { append(s); }
                });
            }
        }).start();
    }

    private void refreshStatus() {
        new Thread(new Runnable() {
            public void run() {
                final String st = sh("sh " + MOD + "/kai status 2>&1");
                ui.post(new Runnable() {
                    public void run() {
                        status.setText(st.replace("\n", "    ").trim());
                    }
                });
            }
        }).start();
    }
}
