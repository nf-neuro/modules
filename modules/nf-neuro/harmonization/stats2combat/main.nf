process HARMONIZATION_STATS2COMBAT {
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    path(stats_files, arity: '1..*')

    output:
    path("*.csv"),               emit: stats_for_combat
    path("versions.yml"),        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def covariates = task.ext.covariates ?: ["sample", "roi", "site", "age", "sex", "handedness", "disease"]
    def covariatespy = "[" + covariates.collect { "\"${it}\"" }.join(", ") + "]"
    def file_list = stats_files.collect { "\"${it}\"" }.join(", ")
    def value_col_name = task.ext.value_col_name ?: "mean"
    def metric_col_name = task.ext.metric_col_name ?: "metric"
    def suffix = task.ext.suffix ?: "raw"

    """
    #!/usr/bin/env python

    import pandas as pd
    import platform

    rename_map = {
        "sample": "sid",
        "roi": "bundle"
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

    # Melt to long format for harmonization
    metric_cols = [col for col in full_df.columns if col not in non_metric_cols]
    full_df = full_df.melt(id_vars=non_metric_cols, value_vars=metric_cols, var_name="${metric_col_name}", value_name="${value_col_name}")

    # Save a separated file for each site and for each metric
    # This is the format the harmonization tool expects as input

    for site, group in full_df.groupby("site"):
        for metric in group["metric"].unique():
            metric_group = group[group["metric"] == metric]
            output_file = f"{site}.{metric}.${suffix}.csv"
            metric_group.to_csv(output_file, index=False)

    # Write versions file (this is in python)
    with open("versions.yml", "w") as f:
        f.write("${task.process}:\\n")
        f.write(f"    python: {platform.python_version()}\\n")
        f.write(f"    pandas: {pd.__version__}\\n")
    """

    stub:
    def covariates = task.ext.covariates ?: ["sample", "roi", "site", "age", "sex", "handedness", "disease"]
    def covariatespy = "[" + covariates.collect { "\"${it}\"" }.join(", ") + "]"
    def file_list = stats_files.collect { "\"${it}\"" }.join(", ")
    def suffix = task.ext.suffix ?: "raw"

    // Extract the sitename from the input files
    // this is to avoid file name collisions when stubbing
    def sitename = stats_files[0].getName().split("\\.")[0]

    """
    #!/usr/bin/env python

    import pandas as pd
    import platform

    with open("${sitename}.metric1.${suffix}.csv", "w") as f:
        pass
    with open("${sitename}.metric2.${suffix}.csv", "w") as f:
        pass

    # Write versions file (this is in python)
    with open("versions.yml", "w") as f:
        f.write("${task.process}:\\n")
        f.write(f"    python: {platform.python_version()}\\n")
        f.write(f"    pandas: {pd.__version__}\\n")
    """
}
