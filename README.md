# ButterCut

This is the source code for the core ButterCut XML generator and video editing agent. If you love or hate Docker, have opinions on types, and have a favorite text editor, this is the spot for you. Otherwise, we recommend following the installation instructions on [ButterCut.io](https://buttercut.io).

## Videos

<table>
  <tr>
    <td align="center"><a href="https://www.youtube.com/watch?v=FBkfr1yWf_s"><img src="https://img.youtube.com/vi/FBkfr1yWf_s/maxresdefault.jpg" alt="I Taught Claude Code to Edit Movies" width="380"></a></td>
    <td align="center"><a href="https://www.youtube.com/watch?v=BCMQzg-HiTw"><img src="https://img.youtube.com/vi/BCMQzg-HiTw/maxresdefault.jpg" alt="ButterCut Install Video" width="380"></a></td>
  </tr>
  <tr>
    <td align="center"><em>Watch the demo: "I Taught Claude Code to Edit Movies"</em></td>
    <td align="center"><em>Watch the ButterCut install video</em></td>
  </tr>
</table>

## Getting Started

ButterCut targets Macs with Apple Silicon (M-series chips). If you're technical and don't mind agent churn, you can likely get it working on Windows, Linux, etc. — but until revenue from ButterCut Pro is full time ish (🤞), broad Windows/Linux compatibility isn't a priority and isn't something I'll publicly support for non-technical users.

Clone this repository and then set it as your active directory.

```bash
git clone https://github.com/barefootford/buttercut.git && cd buttercut
```

Call the `/setup` skill to automatically install dependencies, or see [advanced-setup.md](skills/setup/advanced-setup.md) for a custom install. Primary requirements are Ruby, Python, FFmpeg (full), and WhisperX. Check `.python-version` and `.ruby-version` for specific language versions, and `Gemfile` and `requirements.txt` for their respective dependencies.

## Usage

ButterCut has two primary abstractions: libraries (where footage goes) and cuts (the agent builds a select, scene, or roughcut with you).

See [docs/usage.md](docs/usage.md) for working with libraries and cuts.

## License

ButterCut is open source under the [PolyForm Noncommercial License 1.0.0 with a Commercial Output exception](LICENSE).

- **You absolutely can use ButterCut to make commercial videos.** Cut a YouTube video for ad revenue, edit a paid client project, deliver a sponsored brand piece — all fine. The videos are yours, and the licensor claims no rights to them.
- **You can't repackage ButterCut as commercial software.** Selling, hosting, or bundling the tool itself (or a fork of it) into a commercial product, plugin, or SaaS requires a separate commercial license from TubeSalt LLC.

Personal, hobby, research, and educational use of the software is also free under the underlying license. If you'd like a commercial software license, reach out to [Andrew@TubeSalt.com](mailto:Andrew@TubeSalt.com).

## Future features

This is the core (basic) version of ButterCut. ButterCut Pro is also on the way, à la Sidekiq Pro. ButterCut will remain a single-track editing solution with WhisperX transcription. ButterCut Pro will support multiple tracks, faster transcription, and other "pro" features. If you're a developer interested in a reduced-cost Pro license in exchange for bug reports, DM me on the ButterCut Discord linked from [buttercut.io](https://buttercut.io).

## Contributing

### Start with an issue, not a PR

Thanks to LLMs, it's really easy to spike a quick change to ButterCut — add a feature, fix a bug, etc. But it's still quite difficult to keep code cohesive and maintain working XML across three different editors. If you want to contribute, the best way to start is with a GitHub issue. Write a human-generated issue (I know!), and I'll work with you from there to get a commit in. I'm happy to pair, jump on a Google Meet, etc., to provide context and help get it over the finish line.

Alternatively, you can always *create your own custom skills* (or fork existing ones) and prefix them with `user-`, e.g. `user-quick-interview-summary`. User skills stays on your own Mac, .gitignored, so you can build custom workflows while staying on main. Include your own Ruby or Python scripts inside the skill folder for maximum power without needing a fork.

#### Legal

When you submit a pull request, you give up any rights or claims to the changes you submit to the ButterCut/TubeSalt project, and you assign the copyright for those changes to TubeSalt LLC.

If you can't or don't want to reassign those rights — for example, your employment contract may not allow it — don't submit a pull request. Instead, open an issue, and someone else can do the work.

In plain terms: when you submit a pull request to us, that code becomes ours. Most of the time, that's what you intend anyway, and we hope it doesn't scare you away from contributing.

## Thanks

ButterCut was inspired by ambitious open source work from [Chris Hocking](https://github.com/CommandPost/CommandPost) and [Andrew Arrow](https://github.com/andrewarrow/cutlass/tree/main).
