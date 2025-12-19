process STATS_METRICSINROI {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:dev"

    input:
    tuple val(meta), path(metrics), path(rois), path(rois_lut)  /* optional, input = [] */

    output:
    tuple val(meta), path("*.json")                   , emit: stats_json
    tuple val(meta), path("*_desc-mean_*.{csv,tsv}")  , emit: stats_mean
    tuple val(meta), path("*_desc-std_*.{csv,tsv}")   , emit: stats_std
    path "versions.yml"                               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_stats" : "stats"
    def bin = task.ext.bin ? "--bin " : ""
    def normalize_weights = task.ext.normalize_weights ? "--normalize_weights " : ""
    def use_label = task.ext.use_label ? true : false
    def key_substrs_to_remove = task.ext.key_substrs_to_remove ?: []
    def value_substrs_to_remove = task.ext.value_substrs_to_remove ?: []

    def meta_columns = task.ext.meta_columns ?: []
    def meta_columns_values  = meta_columns.collect { col -> meta.containsKey(col) ? meta[col] : "null" }

    def output_format = task.ext.output_format ?: 'tsv'  // 'csv' or 'tsv'

    assert output_format in ['csv', 'tsv'] : "output_format must be either 'csv' or 'tsv'"

    def sep = output_format == 'tsv' ? '\t' : ','
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    if $use_label;
    then
        if [[ ! -f "$rois_lut" ]];
        then
            echo "ROI LUT is missing. Will fail."
        fi

        scil_volume_stats_in_labels $rois $rois_lut \
            --metrics $metrics \
            --sort_keys > ${prefix}_${suffix}.json
    else
        scil_volume_stats_in_ROI $rois \
            --metrics $metrics \
            --sort_keys \
            --keep_unique_roi_name \
            $bin $normalize_weights > ${prefix}_${suffix}.json
    fi

    # Remove all substrings from the keys as specified
    # in the configuration via 'task.ext.key_substrs_to_remove'
    for substr in ${key_substrs_to_remove.join(' ')};
    do
        SUBSTR="\$substr" jq -r '
            with_entries(.key |= sub(env.SUBSTR; ""))
        ' ${prefix}_${suffix}.json > ${prefix}_${suffix}_tmp.json
        mv ${prefix}_${suffix}_tmp.json ${prefix}_${suffix}.json
    done

    # Extract 'desc' substring from keys and store it temporarily in values
    # This allows us to remove the substring from the key now and append it later
    jq -r '
        with_entries(
            .value |= with_entries(
                if (.key | test("_desc-[a-zA-Z0-9]+")) then
                    (.key | capture("_desc-(?<desc>[a-zA-Z0-9]+)").desc) as \$d |
                    .key |= sub("_desc-[a-zA-Z0-9]+"; "") |
                    .key |= if \$d == "fwc" then . + "t" else . + "_" + \$d end
                else
                    .
                end
            )
        )
    ' ${prefix}_${suffix}.json > ${prefix}_${suffix}_tmp.json
    mv ${prefix}_${suffix}_tmp.json ${prefix}_${suffix}.json

    # Remove all substrings from the values as specified
    # in the configuration via 'task.ext.value_substrs_to_remove'
    for substr in ${value_substrs_to_remove.join(' ')};
    do
        SUBSTR="\$substr" jq -r '
            with_entries(
                .value |= with_entries(
                    .key |= sub(env.SUBSTR; "")
                )
            )
        ' ${prefix}_${suffix}.json > ${prefix}_${suffix}_tmp.json
        mv ${prefix}_${suffix}_tmp.json ${prefix}_${suffix}.json
    done

    # Append the extracted 'desc' to the keys, before the extension if present
    jq -r '
        with_entries(
            .value |= with_entries(
                if (.value.extracted_desc) then
                    (.value.extracted_desc) as \$d |
                    del(.value.extracted_desc) |
                    .key |= if test("\\\\.") then sub("(?<base>.*?)(?<ext>\\\\..*)\$"; .base + "_" + \$d + .ext) else . + "_" + \$d end
                else
                    .
                end
            )
        )
    ' ${prefix}_${suffix}.json > ${prefix}_${suffix}_tmp.json
    mv ${prefix}_${suffix}_tmp.json ${prefix}_${suffix}.json

    # Get all ROIs names from the JSON
    rois=\$(jq -r "keys[]" ${prefix}_${suffix}.json)

    # All ROIs have the same metrics. To get the metrics names from
    # the JSON, we can just fetch them from the first ROI.
    first_roi=\$(printf '%s\\n' \$rois | head -n 1)

    # Extract the metrics names from this first roi
    metrics=\$(FIRST_ROI="\$first_roi" jq -r ".\\"\$first_roi\\" | keys[]" ${prefix}_${suffix}.json)

    # Create the CSV/TSV headers
    # (sample, roi, metric1, metric2, ..., metricN)
    header_mean="sample${sep}roi"
    header_std="sample${sep}roi"

    # Create the meta columns
    for meta_col in ${meta_columns.join(' ')}; do
        header_mean="\${header_mean}${sep}\${meta_col}"
        header_std="\${header_std}${sep}\${meta_col}"
    done

    # Add the metric columns
    for metric in \$metrics; do
        header_mean="\${header_mean}${sep}\${metric}"
        header_std="\${header_std}${sep}\${metric}"
    done
    echo "\$header_mean" > ${prefix}_desc-mean_${suffix}.${output_format}
    echo "\$header_std" > ${prefix}_desc-std_${suffix}.${output_format}

    for roi in \$rois;
    do
        # Initialize lines with sample and roi
        line_mean="${prefix}${sep}\${roi}"
        line_std="${prefix}${sep}\${roi}"

        # Add meta columns values if specified
        for meta_val in ${meta_columns_values.join(' ')}; do
            if [ "\${meta_val}" == "null" ]; then
                line_mean="\${line_mean}${sep}" # no value = empty string
                line_std="\${line_std}${sep}" # no value = empty string
            else
                line_mean="\${line_mean}${sep}\${meta_val}"
                line_std="\${line_std}${sep}\${meta_val}"
            fi
        done

        for metric in \$metrics;
        do
            # Fetch the "mean" and "std" values from each roi/metric
            # pair from the JSON
            val_mean=\$(jq -r --arg ROI "\$roi" --arg METRIC "\$metric" '.[\$ROI].[\$METRIC].mean' ${prefix}_${suffix}.json)
            val_std=\$(jq -r --arg ROI "\$roi" --arg METRIC "\$metric" '.[\$ROI].[\$METRIC].std' ${prefix}_${suffix}.json)

            # Append values to the lines
            line_mean="\${line_mean}${sep}\${val_mean}"
            line_std="\${line_std}${sep}\${val_std}"
        done

        # Append the completed lines to the files
        echo "\$line_mean" >> ${prefix}_desc-mean_${suffix}.${output_format}
        echo "\$line_std" >> ${prefix}_desc-std_${suffix}.${output_format}
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        jq: \$(jq --version |& sed '1!d ; s/jq-//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_stats" : "stats"
    def output_format = task.ext.output_format ?: 'tsv'  // 'csv' or 'tsv'
    assert output_format in ['csv', 'tsv'] : "output_format must be either 'csv' or 'tsv'"
    """
    scil_volume_stats_in_ROI -h
    scil_volume_stats_in_labels -h

    touch ${prefix}_${suffix}.json
    touch ${prefix}_desc-mean_${suffix}.${output_format}
    touch ${prefix}_desc-std_${suffix}.${output_format}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        jq: \$(jq --version |& sed '1!d ; s/jq-//')
    END_VERSIONS
    """
}
