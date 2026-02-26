process HARMONIZATION_COMBAT2STATS {
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    path(harmonized_stats, arity: '1..*')

    output:
    path("*.tsv"),               emit: stats_for_mqc
    path("versions.yml"),        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def covariates = task.ext.covariates ?: ["sample", "roi", "site", "age", "sex", "handedness", "disease"]
    def covariatespy = "[" + covariates.collect { "\"${it}\"" }.join(", ") + "]"
    def file_list = harmonized_stats.collect { "\"${it}\"" }.join(", ")
    def value_col_name = task.ext.value_col_name ?: "mean"
    def metric_col_name = task.ext.metric_col_name ?: "metric"
    def suffix = task.ext.suffix ?: "harmonized"

    """
    #!/usr/bin/env python

    import pandas as pd
    import platform

    rename_map = {
        "sid": "sample",
        "bundle": "roi"
    }
    non_metric_cols = [rename_map.get(col, col) for col in ${covariatespy}]

    dataframes = []
    for file in [${file_list}]:
        df = pd.read_csv(file, sep="\\t" if (file.endswith(".tsv") or file.endswith(".tsv.gz")) else ",")
        df = df.rename(columns=rename_map)
        dataframes.append(df)

    # Make sure all dataframes have the same columns
    for df in dataframes:
        if set(df.columns) != set(dataframes[0].columns):
            raise ValueError("All input files must have the same columns")

    # Concat all dataframes
    full_df = pd.concat(dataframes, ignore_index=True)

    # Pivot back to wide format
    full_df = full_df.pivot_table(index=non_metric_cols, columns="${metric_col_name}", values="${value_col_name}").reset_index()

    # Save a separated file for each site which aggregates all metrics
    # This is the format that is excpected by MultiQC down the line.
    for site, group in full_df.groupby("site"):
        output_file = f"{site}.${suffix}.tsv"
        group.to_csv(output_file, sep="\\t", index=False)

    # Write versions file (this is in python)
    with open("versions.yml", "w") as f:
        f.write("${task.process}:\\n")
        f.write(f"    python: {platform.python_version()}\\n")
        f.write(f"    pandas: {pd.__version__}\\n")
    """

    stub:
    def covariates = task.ext.covariates ?: ["sample", "roi", "site", "age", "sex", "handedness", "disease"]
    def file_list = harmonized_stats.collect { "\"${it}\"" }.join(", ")
    def covariatespy = "[" + covariates.collect { "\"${it}\"" }.join(", ") + "]"

    // Extract the sitename from the input files
    // this is to avoid file name collisions when stubbing
    def sitename = harmonized_stats[0].getName().split("\\.")[0]

    """
    #!/usr/bin/env python

    import pandas as pd
    import platform

    with open("${sitename}.harmonized.tsv", "w") as f:
        pass

    # Write versions file (this is in python)
    with open("versions.yml", "w") as f:
        f.write("${task.process}:\\n")
        f.write(f"    python: {platform.python_version()}\\n")
        f.write(f"    pandas: {pd.__version__}\\n")
    """
}
