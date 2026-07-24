use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::process::ExitCode;
use ums_profiles::{compile_idaptik, read_and_validate_declared_profile, write_pretty_json};

#[derive(Parser)]
#[command(
    name = "ums-profile",
    version,
    about = "Validate and compile isolated UMS game profiles"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    CompileIdaptik {
        #[arg(long)]
        source: PathBuf,
        #[arg(long)]
        idaptik_root: PathBuf,
        #[arg(long)]
        output: PathBuf,
    },
    Validate {
        #[arg(long)]
        profile: PathBuf,
        #[arg(long)]
        fixture: PathBuf,
    },
}

fn main() -> ExitCode {
    let result = match Cli::parse().command {
        Command::CompileIdaptik {
            source,
            idaptik_root,
            output,
        } => compile_idaptik(&source, &idaptik_root)
            .and_then(|package| write_pretty_json(&output, &package))
            .map(|()| println!("compiled {}", output.display())),
        Command::Validate { profile, fixture } => {
            read_and_validate_declared_profile(&profile, &fixture)
                .map(|()| println!("valid {}", fixture.display()))
        }
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("profile error: {error}");
            ExitCode::FAILURE
        }
    }
}
