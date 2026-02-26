process TRACTOGRAM_RESAMPLE {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(tractograms)

    output:
        tuple val(meta), path("*_resampled.trk")       , emit: tractograms
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def nb_points = task.ext.nb_points ?: 1
    def nb_streamlines = task.ext.nb_streamlines ?: 1000
    def never_upsample = task.ext.never_upsample ? "--never_upsample " : ""
    def seed = task.ext.seed ? "--seed ${task.ext.seed} " : ""
    def point_wise_std = task.ext.point_wise_std ? "--point_wise_std ${task.ext.point_wise_std} " : ""
    def tube_radius = task.ext.tube_radius ? "--tube_radius ${task.ext.tube_radius} " : ""
    def gaussian = task.ext.gaussian ? "--gaussian ${task.ext.gaussian} " : ""
    def compress = task.ext.compress ? "--compress ${task.ext.compress} " : ""
    def keep_invalid = task.ext.keep_invalid ? "--keep_invalid " : ""
    def downsample_per_cluster = task.ext.downsample_per_cluster ? "--downsample_per_cluster " : ""
    def qbx_threshold = task.ext.qbx_threshold ? "--qbx_threshold ${task.ext.qbx_threshold} " : ""

    """
    for tractogram in ${tractograms};
        do
        ext=\${tractogram#*.}

        if [[ $nb_points -gt 1 ]]; then
            if [[ \$tractogram == *"__"* ]]; then
                pos=\$((\$(echo \$tractogram | grep -b -o __ | cut -d: -f1)+2))
                bname=\${tractogram:\$pos}
                bname=\$(basename \$bname .\${ext})
            else
                bname=\$(basename \$tractogram .\${ext})
            fi

            scil_tractogram_resample_nb_points \$tractogram \
                "${prefix}_\${bname}_resampled.\${ext}" \
                --nb_pts_per_streamline $nb_points -f
        else
            bname=\$(basename \${tractogram} .\${ext})

            scil_tractogram_resample \$tractogram $nb_streamlines \
                "${prefix}_\${bname}_resampled.\${ext}" \
                $never_upsample $seed $point_wise_std $tube_radius \
                $gaussian $compress $keep_invalid \
                $downsample_per_cluster $qbx_threshold
        fi
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_tractogram_resample_nb_points -h
    scil_tractogram_resample -h

    for tractogram in ${tractograms};
        do \
        ext=\${tractogram#*.}
        bname=\$(basename \${tractogram} .\${ext})
        touch ${prefix}__\${bname}_resampled.\${ext}
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
