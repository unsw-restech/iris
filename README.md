# IRIS — the ResTech AI Imaging Gateway

IRIS is a catalogue of imaging analysis workflows that UNSW researchers launch on Katana, UNSW's computing cluster, from their browser. Each workflow has a page saying what it does and what data it needs, and a **Run on Katana** button that opens a form: fill it in, submit, and the job runs on Katana with your data in your own scratch space.

**Website**: https://patricktung.github.io/iris/

> **IRIS is not open to researchers yet.** Its workflows are still being tested, and their Run buttons lead to a test instance you can't use. If you'd like to use IRIS, or try it before launch, email patrick.tung@unsw.edu.au.

IRIS used to be called ARES. The old `patricktung.github.io/ares/` address no longer works.

## Before you start

- **A Katana account.** You need a UNSW zID and a staff, student or other relationship with UNSW. Apply to ResTech, as their [FAQ](https://docs.restech.unsw.edu.au/help_support/faq/) explains; IRIS can't create accounts.
- **The UNSW VPN when off campus.** Katana OnDemand, where IRIS forms run, is only reachable on campus or through the VPN.
- **Space in your scratch**, `/srv/scratch/<zID>`. Every run reads its dataset from there and writes its results back beside it.

## How a run goes

1. **Stage** a dataset: lay out its folder and copy it into your scratch. The [guide](https://patricktung.github.io/iris/guide/#stage) shows how. Do this once per dataset.
2. **Launch** a workflow from the [catalogue](https://patricktung.github.io/iris/): click **Run on Katana** on its page, check the form and submit.
3. **View and compare** your runs with `iris-view` and `iris-compare`, as the [guide](https://patricktung.github.io/iris/guide/#view) shows. When a job finishes, its output gives you both commands ready to paste.

New to Katana? Run [Hello World](https://patricktung.github.io/iris/workflows/hello-world/) first. It needs no data and checks that your access works.

## What's in this repo

You don't need anything here to use IRIS; the website and forms are enough. The repo is for reading the code your runs used.

| Path | What it is |
|---|---|
| `workflows/<workflow>/src/` | The code a workflow's jobs run |
| `lib/iris/` | Code shared by imaging workflows: reading volumes, writing label volumes, recording runs |
| `bin/iris-view`, `bin/iris-compare`, `bin/iris-rebuild` | Your tools: view a run, compare runs, and rebuild your tracking store if it is lost |
| `envs/imaging/` | The software, with exact versions, that imaging runs use |

Every run writes `commit.txt` into its run directory: the exact commit of this repo it ran, so you can see the code behind any result.

Building or changing a workflow? See [CONTRIBUTING.md](CONTRIBUTING.md).

## Contact

- **IRIS**: its workflows, a failed run, or reusing its code: patrick.tung@unsw.edu.au
- **Katana itself**: accounts, access, scratch quotas and anything else that needs a Katana administrator go to ResTech support, restech.support@unsw.edu.au, as the [ResTech FAQ](https://docs.restech.unsw.edu.au/help_support/faq/) explains.
