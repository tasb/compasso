# The shape both trackers' snapshot commands return (bin/tracker/gitlab.sh, github.sh).
# snapshot(issues; mrs; main), where each issue is {iid, title, web_url, labels, description, deps, type}
#   (type: GitLab's issue_type, task for a story; null on GitHub)
#   (and feature: the story's feature number, from its Feature line, or null; sprint: {title, due} of its milestone, or null)
# and each merge request {iid, title, web_url, draft, labels, branch, description, author, pipeline}:
#   issues: [{iid, title, web_url, labels, kind: story|bug|feature|ask|later|other, state, dev, feature, sprint, needs_human, blocked_by, ask_for, ask_key}]
#           state is the compasso:: label without its prefix; blocked_by keeps only dependencies still open;
#           later is the after-MVP list (bin/lead.sh later); an ask is a needs::human issue a Compasso agent opened, ask_for the story it holds back and
#           ask_key its key (bin/run.sh: a stuck job stays skipped while its stuck-<key> question is open)
#   mrs:    [{iid, title, web_url, labels, story, branch, draft, rework, author, pipeline: success|failed|running|...|none}]
#   main:   {pipeline: success|failed|none, sha}: the default branch's last finished pipeline

def ask_marker: (.description | capture("<!-- compasso:ask story=(?<s>[0-9]*)")? | .s) // null;
def ask_key: (.description | capture("<!-- compasso:ask story=[0-9]* key=(?<k>[^ ]+)")? | .k) // null;
def scoped($prefix): [.labels[] | select(startswith($prefix)) | ltrimstr($prefix)][0] // null;

def snapshot($issues; $mrs; $main):
  ($issues | map(.iid)) as $open
  | {
      issues: ($issues | map(. as $i | ask_marker as $ask | {
        iid, title, web_url, labels,
        kind: (if $ask != null then "ask"
               elif .description | startswith("<!-- compasso:after-mvp list -->") then "later"
               elif (.labels | index("type::bug")) then "bug"
               elif (.labels | index("type::feature")) then "feature"
               elif (.labels | any(IN("type::epic", "type::blocker", "compasso::after-mvp"))) then "other"
               elif (.labels | any(IN("type::story", "type::task"))) then "story"
               # a story need not say so: on GitLab it is a task, on GitHub an issue given to a developer or an owner
               elif .type == "task" or (.type == null and (.labels | any(startswith("dev::") or startswith("owner::")))) then "story"
               else "other" end),
        state: scoped("compasso::"),
        dev: scoped("dev::"),
        feature: (.feature // null),
        sprint: (.sprint // null),
        needs_human: (.labels | index("needs::human") != null),
        blocked_by: [.deps[] | select(. as $d | $open | index($d))] | unique,
        ask_for: (if $ask == null or $ask == "" then null else ($ask | tonumber) end),
        ask_key: ask_key
      })),
      mrs: ($mrs | map({
        iid, title, web_url, labels, branch, draft, author, pipeline,
        story: ((.branch | capture("^(story|bug|fix)/(?<n>[0-9]+)")? | .n | tonumber)
                // (.description | capture("(?i)(closes|fixes|resolves) #(?<n>[0-9]+)")? | .n | tonumber) // null),
        rework: (.labels | index("compasso::rework") != null)
      })),
      main: $main
    };
