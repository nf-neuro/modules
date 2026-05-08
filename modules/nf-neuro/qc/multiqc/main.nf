process QC_MULTIQC {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "gagnonanthony/multiqc-neuroimaging:0.1.3"
        containerOptions((workflow.containerEngine == 'docker') ? '--entrypoint "" --user $(id -u):$(id -g)' : '')

    input:
    tuple val(meta), path(qc_images)
    path  multiqc_files
    path(multiqc_config)
    path(extra_multiqc_config)
    path(multiqc_logo)
    path(replace_names)
    path(sample_names)

    output:
    val (meta)                 , emit: meta // meta field required for linting.
    path "*.html"              , emit: report
    path "*_data"              , emit: data
    path "*_plots"             , optional:true, emit: plots
    path "versions.yml"        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ? "$task.ext.prefix-${workflow.start.format('yyMMdd-HHmm')}" : "${meta.id}-${workflow.start.format('yyMMdd-HHmm')}"
    def config = multiqc_config ? "--config $multiqc_config" : ''
    def extra_config = extra_multiqc_config ? "--config $extra_multiqc_config" : ''
    def logo = multiqc_logo ? "--cl-config 'custom_logo: \"${multiqc_logo}\"'" : ''
    def replace = replace_names ? "--replace-names ${replace_names}" : ''
    def samples = sample_names ? "--sample-names ${sample_names}" : ''
    def single_subject = task.ext.single_subject ? "--single-subject-report" : ""
    def cortical_rois = task.ext.cortical_rois ? "--cortical-rois ${task.ext.cortical_rois}" : ''
    def subcortical_rois = task.ext.subcortical_rois ? "--subcortical-rois ${task.ext.subcortical_rois}" : ''

    """
    multiqc \\
        --force \\
        $args \\
        $config \\
        --filename ${prefix}.html \\
        $extra_config \\
        $logo \\
        $replace \\
        $samples \\
        $single_subject \\
        $cortical_rois \\
        $subcortical_rois \\
        .

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        multiqc: \$( multiqc --version | sed -e "s/multiqc, version //g" )
        neuroimaging: \$( pip list | grep neuroimaging | awk '{print \$2}' )
    END_VERSIONS
    """

    stub:
    def prefix = "${meta.id}" // No timestamp in stub, otherwise tests will fail.

    """
    multiqc --help

    mkdir ${prefix}_multiqc_data
    mkdir ${prefix}_multiqc_plots
    touch ${prefix}_multiqc_report.html

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        multiqc: \$( multiqc --version | sed -e "s/multiqc, version //g" )
        neuroimaging: \$( pip list | grep neuroimaging | awk '{print \$2}' )
    END_VERSIONS
    """
}
