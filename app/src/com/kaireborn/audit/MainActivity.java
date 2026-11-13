package com.kaireborn.audit;

import android.app.Activity;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.List;

/**
 * KaiReborn — device-audit companion.
 *
 * Design notes, deliberately different from the legacy app:
 *
 *  - It never calls `pm clear`, `rm` under /data/system, `mount -o remount`,
 *    or writes a module hook. Its only write paths are:
 *      (a) the module's state/extra.prop, and
 *      (b) a read-only report in the module's logs/ directory.
 *  - No AdvertisingIdClient. The legacy app read the GAID and stored it in a
 *    backup JSON; that is a privacy leak in the opposite direction and buys
 *    nothing, because the GAID lives in Play Services and cannot be spoofed by
 *    an ordinary app.
 *  - No network. Nothing leaves the device.
 *  - The ID view is read-only by construction: it reads settings_ssaid.xml and
 *    GMS's adid_settings.xml and prints the values. Reset is a button that
 *    delegates to the platform's own mechanism, not to file surgery.
 */
public class MainActivity extends Activity {

    private static final String MOD = "/data/adb/modules/kaireborn";

    private TextView status;
    private TextView output;
    private EditText name;
    private EditText value;
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        status = new TextView(this);
        status.setText("checking…");
        status.setTextSize(13);

        Button audit = new Button(this);
        audit.setText("Run read-only audit");
        audit.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { runAudit(); }
        });

        Button idBtn = new Button(this);
        idBtn.setText("Show identifiers (read-only)");
        idBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { showIds(); }
        });

        Button addBtn = new Button(this);
        addBtn.setText("Add property override");
        addBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { addOverride(); }
        });

        name = new EditText(this);
        name.setHint("property name, e.g. ro.product.model");
        name.setTextSize(13);
        value = new EditText(this);
        value.setHint("value");
        value.setTextSize(13);

        Button resetGaia = new Button(this);
        resetGaia.setText("Open system Ad-ID settings");
        resetGaia.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                try {
                    startActivity(new android.content.Intent(
                            android.provider.Settings.ACTION_PRIVACY_SETTINGS));
                } catch (Exception e) {
                    append("cannot open settings: " + e.getMessage());
                }
            }
        });

        output = new TextView(this);
        output.setTextSize(11);
        output.setTextIsSelectable(true);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(output);

        root.addView(status);
        root.addView(audit);
        root.addView(idBtn);
        root.addView(name);
        root.addView(value);
        root.addView(addBtn);
        root.addView(resetGaia);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
        refreshStatus();
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    private void append(String s) {
        output.append(s + "\n");
    }

    private void refreshStatus() {
        new Thread(new Runnable() {
            public void run() {
                final boolean hasRoot = rootOk();
                final boolean hasModule = new File(MOD, "module.prop").exists();
                final String impl = sh("cat " + MOD + "/state/mode 2>/dev/null").trim();
                ui.post(new Runnable() {
                    public void run() {
                        status.setText("root: " + (hasRoot ? "yes" : "no")
                                + "   module: " + (hasModule ? "installed" : "missing")
                                + "   mode: " + (impl.isEmpty() ? "?" : impl));
                    }
                });
            }
        }).start();
    }

    // --- root plumbing ------------------------------------------------------

    private boolean rootOk() {
        return sh("id").contains("uid=0");
    }

    /** Runs through `su -c`, the same primitive the legacy app used. */
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

    // --- read-only screens --------------------------------------------------

    private void runAudit() {
        output.setText("");
        append("── audit ──");
        new Thread(new Runnable() {
            public void run() {
                final String out = sh("sh " + MOD + "/audit.sh");
                ui.post(new Runnable() {
                    public void run() {
                        append(out.isEmpty() ? "(no output — module not installed?)" : out);
                    }
                });
            }
        }).start();
    }

    /**
     * Reads identifiers without changing them.
     *
     * settings_ssaid.xml is Android Binary XML; we do not parse it, we only
     * report that it exists and how many entries it holds, because parsing
     * formats is exactly where the legacy app got the semantics wrong.
     */
    private void showIds() {
        output.setText("");
        append("── identifiers (read-only) ──");
        new Thread(new Runnable() {
            public void run() {
                StringBuilder sb = new StringBuilder();

                String adid = sh("cat /data/user/0/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null");
                sb.append("Advertising ID file:\n");
                if (adid.trim().isEmpty()) {
                    sb.append("  (not present — Play Services has no GAID yet)\n");
                } else {
                    for (String l : adid.split("\n")) {
                        String t = l.trim();
                        if (t.startsWith("<string") || t.startsWith("<boolean") || t.startsWith("<long"))
                            sb.append("  ").append(t).append('\n');
                    }
                }

                String ssaid = sh("ls -l /data/system/users/0/settings_ssaid.xml 2>/dev/null");
                sb.append("\nAndroid ID (SSAID) store:\n");
                sb.append("  ").append(ssaid.trim().isEmpty() ? "missing" : ssaid.trim()).append('\n');
                sb.append("  entries: ")
                  .append(sh("grep -c 'com\\.' /data/system/users/0/settings_ssaid.xml 2>/dev/null").trim())
                  .append('\n');
                sb.append("  note: values are per-app and regenerated by the platform\n");
                sb.append("        when the store is removed. This app never edits them.\n");

                sb.append("\nBuild identity:\n");
                String[] props = {
                        "ro.product.manufacturer", "ro.product.model", "ro.product.brand",
                        "ro.product.device", "ro.build.fingerprint", "ro.build.version.release",
                        "ro.build.version.sdk", "ro.build.tags", "ro.build.type"
                };
                for (String p : props) {
                    sb.append("  ").append(p).append(" = ")
                      .append(sh("getprop " + p).trim()).append('\n');
                }

                final String s = sb.toString();
                ui.post(new Runnable() {
                    public void run() { append(s); }
                });
            }
        }).start();
    }

    /**
     * Appends one NAME=VALUE line to the module's user-override file.
     * The module applies it on the next boot, through its guarded,
     * verify-after-write path. No direct property writes from here on purpose.
     */
    private void addOverride() {
        final String n = name.getText().toString().trim();
        final String v = value.getText().toString().trim();
        if (n.isEmpty() || v.isEmpty()) {
            append("need both a name and a value");
            return;
        }
        if (!n.matches("[a-zA-Z0-9_.\\-]+")) {
            append("invalid property name");
            return;
        }
        new Thread(new Runnable() {
            public void run() {
                String cmd = "mkdir -p " + MOD + "/state >/dev/null 2>&1; "
                        + "printf '%s\\n' '" + n + "=" + v + "' >> " + MOD + "/state/extra.prop; "
                        + "cat " + MOD + "/state/extra.prop";
                final String res = sh(cmd);
                ui.post(new Runnable() {
                    public void run() {
                        append("override queued (applies next boot):");
                        append(res);
                        name.setText("");
                        value.setText("");
                    }
                });
            }
        }).start();
    }
}
