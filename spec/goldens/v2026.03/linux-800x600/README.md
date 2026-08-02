# Stable framebuffer goldens

Generate these only from the pinned stable KOReader runtime under Linux/Xvfb at
800×600:

```sh
ZEN_UI_RUN_EMULATOR=1 ./spec/run update-goldens
```

In GitHub Actions, run the `Generate Linux Goldens` workflow manually and
download its `linux-goldens` artifact. Review and commit the result; the
workflow deliberately does not push to the repository.

Normal emulator runs compare any committed golden exactly and retain current
images plus RGB diffs under `spec/.artifacts/goldens/`. Do not generate or
review goldens from a host display with a different resolution or font stack.

`fixture-library.png` is the file browser populated from
`spec/fixtures/library`; `fixture-reader.png` opens the committed Wasteland
EPUB from that same corpus. The test normalizes staged file timestamps so sort
order cannot vary by checkout time.
