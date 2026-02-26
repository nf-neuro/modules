process BUNDLE_RECOGNIZE {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(tractograms), path(transform), path(config), path(directory)

    output:
    tuple val(meta), path("*_cleaned.trk")             , emit: bundles
    tuple val(meta), path("*_bundles_mosaic_mqc.png")  , emit: bundles_mqc, optional: true
    tuple val(meta), path("*_bundles_stats_mqc.json")  , emit: stats_mqc, optional: true
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    // additional script arguments
    def minimal_vote_ratio = task.ext.minimal_vote_ratio ? "--minimal_vote_ratio " + task.ext.minimal_vote_ratio : ""
    def seed = task.ext.seed ? "--seed " + task.ext.seed : ""
    def rbx_processes = task.cpus ? "--processes " + task.cpus : "--processes 1"
    def outlier_alpha = task.ext.outlier_alpha ? "--alpha " + task.ext.outlier_alpha : ""
    def run_qc = task.ext.run_qc ?: false
    """
    if [[ "$transform" == *.txt ]]; then
        ConvertTransformFile 3 $transform transform.mat --convertToAffineType \
            && transform="transform.mat" \
            || echo "TXT transform file conversion failed, using original file."
    fi

    mkdir recobundles/
    scil_tractogram_segment_with_bundleseg ${tractograms} ${config} ${directory}/ ${transform} --inverse --out_dir recobundles/ \
        -v DEBUG $minimal_vote_ratio $seed $rbx_processes

    for bundle_file in recobundles/*.trk; do
        bname=\$(basename \${bundle_file} .trk | sed 's/${prefix}_\\+//')
        out_cleaned=${prefix}_\${bname}_cleaned.trk
        scil_bundle_reject_outliers \${bundle_file} "\${out_cleaned}" ${outlier_alpha}
    done

    if $run_qc; then
        # Add commands to run QC here
        echo "Running QC..."

        # Take one file to generate temporary anat

        first_trk=(*_cleaned.trk)
        scil_tractogram_compute_density_map \${first_trk} tmp_anat.nii.gz --binary
        # Generate Mosaic for QC
        scil_viz_bundle_screenshot_mosaic tmp_anat.nii.gz *_cleaned.trk ${prefix}__bundles_mosaic_mqc.png --opacity_background 1

        rm -f tmp_anat.nii.gz

        # Generate JSON file stats
        for curr_bundle in *cleaned.trk; do
            bundle_name=\$(basename \${curr_bundle} _cleaned.trk)
            scil_bundle_shape_measures \${curr_bundle} --out_json \${bundle_name}__stats.json
        done

        scil_json_merge_entries *__stats.json ${prefix}__bundles_stats_mqc.json --keep_separate
        rm -f *__stats.json
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    scil_tractogram_segment_with_bundleseg -h
    scil_bundle_reject_outliers -h
    scil_viz_bundle_screenshot_mosaic -h
    scil_tractogram_compute_density_map -h
    scil_bundle_shape_measures -h
    scil_json_merge_entries -h

    # dummy output for single bundle
    touch ${prefix}_AF_L_cleaned.trk
    touch ${prefix}__bundles_mosaic_mqc.png
    touch ${prefix}__bundles_stats_mqc.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
