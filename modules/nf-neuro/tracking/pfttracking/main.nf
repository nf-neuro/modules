
process TRACKING_PFTTRACKING {
    tag "$meta.id"
    label 'process_high_memory'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(wm), path(gm), path(csf), path(fodf), path(fa)

    output:
        tuple val(meta), path("*__pft_tracking.trk")            , emit: trk
        tuple val(meta), path("*__pft_tracking_config.json")    , emit: config
        tuple val(meta), path("*__map_include.nii.gz")          , emit: includes
        tuple val(meta), path("*__map_exclude.nii.gz")          , emit: excludes
        tuple val(meta), path("*__pft_seeding_mask.nii.gz")     , emit: seeding
        tuple val(meta), path("*__pft_tracking_mqc.png")        , emit: mqc, optional: true
        tuple val(meta), path("*__pft_tracking_stats.json")     , emit: global_mqc, optional: true
        path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def pft_fa_threshold = task.ext.pft_fa_seeding_mask_threshold ?: 0.1
    def pft_wm_threshold = task.ext.pft_wm_seeding_mask_threshold ?: 0.5
    def pft_seeding_mask = task.ext.pft_seeding_mask_type ?: "wm"

    def pft_random_seed = task.ext.pft_random_seed ? "--seed " + task.ext.pft_random_seed : "--seed 0"
    def compress = task.ext.pft_compress_value ? "--compress " + task.ext.pft_compress_value : ""
    def pft_algo = task.ext.pft_algo ? "--algo " + task.ext.pft_algo: ""
    def pft_seeding_type = task.ext.pft_seeding ? "--"  + task.ext.pft_seeding : "--npv"
    def pft_nbr_seeds = task.ext.pft_nbr_seeds ?: 5
    def pft_step = task.ext.pft_step ? "--step "  + task.ext.pft_step : ""
    def pft_step_pct = task.ext.pft_step_pct ? task.ext.pft_step_pct : ""
    def pft_theta = task.ext.pft_theta ? "--theta "  + task.ext.pft_theta : ""
    def pft_sfthres = task.ext.pft_sfthres ? "--sfthres "  + task.ext.pft_sfthres : ""
    def pft_sfthres_init = task.ext.pft_sfthres_init ? "--sfthres_init "  + task.ext.pft_sfthres_init : ""
    def pft_min_len = task.ext.pft_min_len ? "--min_length "  + task.ext.pft_min_len : ""
    def pft_max_len = task.ext.pft_max_len ? "--max_length "  + task.ext.pft_max_len : ""
    def pft_particles = task.ext.pft_particles ? "--particles "  + task.ext.pft_particles : ""
    def pft_back = task.ext.pft_back ? "--back "  + task.ext.pft_back : ""
    def pft_front = task.ext.pft_front ? "--forward "  + task.ext.pft_front : ""
    def basis = task.ext.basis ? "--sh_basis "  + task.ext.basis : ""

    def run_qc = task.ext.run_qc ? task.ext.run_qc : false

    if (pft_step && pft_step_pct) {
        log.warn "Both pft_step and pft_step_pct are set for ${meta.id}. pft_step will take priority and pft_step_pct will be ignored."
    }

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_tracking_pft_maps $wm $gm $csf \
        --include ${prefix}__map_include.nii.gz \
        --exclude ${prefix}__map_exclude.nii.gz \
        --interface ${prefix}__interface.nii.gz -f

    cp $wm tmp_anat_qc.nii.gz

    if [ "${pft_seeding_mask}" == "wm" ]; then
        scil_volume_math lower_threshold $wm $pft_wm_threshold ${prefix}__pft_seeding_mask.nii.gz \
            --data_type uint8 -f
        scil_volume_math union ${prefix}__pft_seeding_mask.nii.gz \
            ${prefix}__interface.nii.gz ${prefix}__pft_seeding_mask.nii.gz \
            --data_type uint8 -f

    elif [ "${pft_seeding_mask}" == "interface" ]; then
        mv ${prefix}__interface.nii.gz ${prefix}__pft_seeding_mask.nii.gz

    elif [ "${pft_seeding_mask}" == "fa" ]; then
        scil_volume_math lower_threshold $fa $pft_fa_threshold \
            ${prefix}__pft_seeding_mask.nii.gz --data_type uint8 -f
    fi

    pft_step_size="$pft_step"
    if [[ -z "$pft_step" ]] && [[ -n "$pft_step_pct" ]]; then
        pixdim=\$(scil_header_print_info $wm --keys pixdim | tr -d '[]' | awk '{for(i=2;i<=4;i++) if(\$i>0 && (\$i<min || min=="")) min=\$i} END {print min}')
        pft_step_size=\$(awk -v pixdim="\$pixdim" -v pct="$pft_step_pct" 'BEGIN {printf "--step %.6f", pixdim * pct / 100}')
    fi

    scil_tracking_pft $fodf ${prefix}__pft_seeding_mask.nii.gz \
        ${prefix}__map_include.nii.gz ${prefix}__map_exclude.nii.gz \
        ${prefix}__pft_tracking.trk \
        $pft_algo $pft_seeding_type $pft_nbr_seeds \
        $pft_random_seed \$pft_step_size $pft_theta \
        $pft_sfthres $pft_sfthres_init $pft_min_len $pft_max_len \
        $pft_particles $pft_back $pft_front $compress $basis -f

    scil_tractogram_remove_invalid ${prefix}__pft_tracking.trk \
        ${prefix}__pft_tracking.trk \
        --remove_single_point -f

    cat <<-TRACKING_INFO > ${prefix}__pft_tracking_config.json
    {"algorithm": "${task.ext.pft_algo}",
    "seeding_type": "${task.ext.pft_seeding}",
    "nb_seed": $task.ext.pft_nbr_seeds,
    "seeding_mask": "${pft_seeding_mask}",
    "random_seed": $task.ext.pft_random_seed,
    "is_compress": "${task.ext.pft_compress_streamlines}",
    "compress_value": $task.ext.pft_compress_value,
    "step": \${pft_step_size/--step /},
    "theta": $task.ext.pft_theta,
    "sfthres": $task.ext.pft_sfthres,
    "sfthres_init": $task.ext.pft_sfthres_init,
    "min_len": $task.ext.pft_min_len,
    "max_len": $task.ext.pft_max_len,
    "particles": $task.ext.pft_particles,
    "back": $task.ext.pft_back,
    "forward": $task.ext.pft_front,
    "sh_basis": "${task.ext.basis}"}
    TRACKING_INFO

    if $run_qc;
    then
        scil_viz_bundle_screenshot_mosaic tmp_anat_qc.nii.gz ${prefix}__pft_tracking.trk\
            ${prefix}__pft_tracking_mqc.png --opacity_background 1 --light_screenshot
        scil_tractogram_print_info ${prefix}__pft_tracking.trk >> ${prefix}__pft_tracking_stats.json
    fi
    rm -f tmp_anat_qc.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_tracking_pft -h
    scil_tracking_pft_maps -h
    scil_volume_math -h
    scil_tractogram_remove_invalid -h
    scil_viz_bundle_screenshot_mosaic -h
    scil_tractogram_print_info -h

    touch ${prefix}__map_include.nii.gz
    touch ${prefix}__map_exclude.nii.gz
    touch ${prefix}__pft_seeding_mask.nii.gz
    touch ${prefix}__pft_tracking.trk
    touch ${prefix}__pft_tracking_config.json
    touch ${prefix}__pft_tracking_mqc.png
    touch ${prefix}__pft_tracking_stats.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
